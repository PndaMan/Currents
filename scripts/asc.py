# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt[crypto]>=2.9", "requests>=2.32"]
# ///
"""App Store Connect tasks that fastlane deliver does not cover.

  status   the latest builds with processing and TestFlight state
  events   create or update the in-app events in ios/AppStore/events
  pages    create or update the custom product pages in ios/AppStore/custom-product-pages
  gamecenter
           turn on Game Center and create or update the achievements,
           leaderboards and challenges in ios/AppStore/game-center
  media    place the app preview and the product page header and search
           results art (ios/build/appstore-media) on the version being prepared

events, pages, gamecenter and media are dry runs unless --apply is given: they read App Store
Connect, print every change they would make, and send no writes. Nothing here
submits anything for review.

Credentials come from the environment: ASC_KEY_ID, ASC_ISSUER_ID and
ASC_KEY_PATH (default ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8).
`make appstore-*` also loads them from .env.local.

API reference: https://developer.apple.com/documentation/appstoreconnectapi
"""

from __future__ import annotations

import argparse
import calendar
import datetime as dt
import hashlib
import threading
from concurrent.futures import ThreadPoolExecutor
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import jwt
import requests

BUNDLE_ID = "com.aidanmcconnon.currents"
BASE_URL = "https://api.appstoreconnect.apple.com"
LOCALE = "en-US"
PHONE_DISPLAY_TYPE = "APP_IPHONE_67"  # the 6.9-inch slot; takes 1320x2868

ROOT = Path(__file__).resolve().parent.parent
APPSTORE_DIR = ROOT / "ios" / "AppStore"
EVENTS_DIR = APPSTORE_DIR / "events"
PAGES_DIR = APPSTORE_DIR / "custom-product-pages"
GAMECENTER_DIR = APPSTORE_DIR / "game-center"
SCREENSHOTS_DIR = Path(os.environ.get("APPSTORE_SCREENSHOTS_DIR") or ROOT / "ios" / "build" / "appstore-screenshots" / "branch")
SCREENSHOTS_SCRIPT = ROOT / "scripts" / "appstore_screenshots.sh"

BADGES = {"LIVE_EVENT", "PREMIERE", "CHALLENGE", "COMPETITION", "NEW_SEASON", "MAJOR_UPDATE", "SPECIAL_EVENT"}
EDITABLE_AFTER_DRAFT = {"territorySchedules", "priority"}

PURPOSES = {
    "appropriate for all users": "APPROPRIATE_FOR_ALL_USERS",
    "attract new users": "ATTRACT_NEW_USERS",
    "keep active users informed": "KEEP_ACTIVE_USERS_INFORMED",
    "bring back lapsed users": "BRING_BACK_LAPSED_USERS",
}
PRIORITIES = {"high": "HIGH", "normal": "NORMAL"}
EVENT_MEDIA = {"EVENT_CARD": "event-card.png", "EVENT_DETAILS_PAGE": "event-details.png"}
MAX_EVENT_DAYS = 31
MAX_PUBLISH_LEAD_DAYS = 14
EDITABLE_PAGE_STATES = {"PREPARE_FOR_SUBMISSION", "REJECTED"}


class ASCError(Exception):
    pass


# ---------------------------------------------------------------- auth + HTTP


@dataclass
class Credentials:
    key_id: str
    issuer_id: str
    key_path: Path

    @classmethod
    def from_env(cls) -> Credentials | None:
        key_id = os.environ.get("ASC_KEY_ID", "").strip()
        issuer_id = os.environ.get("ASC_ISSUER_ID", "").strip()
        if not key_id or not issuer_id:
            return None
        raw = os.environ.get("ASC_KEY_PATH", "").strip() or f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8"
        return cls(key_id, issuer_id, Path(raw).expanduser())


def make_token(creds: Credentials, lifetime: int = 600) -> str:
    """ES256 JWT for the App Store Connect API. Apple allows at most 20 minutes."""
    if not creds.key_path.is_file():
        raise ASCError(f"API key file not found: {creds.key_path} (set ASC_KEY_PATH)")
    now = int(time.time())
    return jwt.encode(
        {"iss": creds.issuer_id, "iat": now, "exp": now + lifetime, "aud": "appstoreconnect-v1"},
        creds.key_path.read_text(),
        algorithm="ES256",
        headers={"kid": creds.key_id, "typ": "JWT"},
    )


def describe_errors(resp: requests.Response) -> str:
    try:
        errors = resp.json().get("errors", [])
    except ValueError:
        return f"HTTP {resp.status_code}: {resp.text[:500]}"
    if not errors:
        return f"HTTP {resp.status_code}: {resp.text[:500]}"
    lines = []
    for e in errors:
        source = e.get("source") or {}
        where = source.get("pointer") or source.get("parameter") or ""
        line = f"HTTP {e.get('status', resp.status_code)} {e.get('code', '')}: {e.get('title', '').rstrip('.')}. {e.get('detail', '')}"
        if where:
            line += f" ({where})"
        lines.append(line.strip())
    return "\n".join(lines)


class Client:
    """App Store Connect client. In dry-run mode reads go through and writes are printed instead."""

    def __init__(self, creds: Credentials | None, apply: bool):
        self.creds = creds
        self.apply = apply
        self.session = requests.Session()
        self._token = ""
        self._token_exp = 0.0
        self._fake = 0
        self.writes = 0
        # Uploads run on worker threads; this guards the token and counters.
        self._lock = threading.Lock()

    @property
    def online(self) -> bool:
        return self.creds is not None

    def _auth(self) -> str:
        with self._lock:
            if time.time() > self._token_exp - 60:
                self._token = make_token(self.creds)
                self._token_exp = time.time() + 600
            return self._token

    def request(self, method: str, path: str, *, params=None, body=None) -> dict:
        if not self.online:
            raise ASCError("no credentials")
        url = path if path.startswith("http") else BASE_URL + path
        delay = 2.0
        for attempt in range(6):
            try:
                resp = self.session.request(
                    method, url, params=params, json=body, timeout=(10, 120),
                    headers={"Authorization": f"Bearer {self._auth()}"},
                )
            except (requests.ConnectionError, requests.Timeout) as exc:
                # A POST that timed out may still have created something, so
                # only reads and idempotent writes are sent again.
                timed_out = isinstance(exc, requests.Timeout) and not isinstance(exc, requests.ConnectTimeout)
                if timed_out and method == "POST":
                    raise ASCError(f"{method} {path}: Apple did not answer in time. Run the command again; "
                                   "it skips whatever was already created.") from exc
                if attempt == 5:
                    raise ASCError(f"{method} {path}: {exc}") from exc
                time.sleep(delay)
                delay *= 2
                continue
            if resp.status_code == 429 or resp.status_code >= 500:
                if attempt == 5:
                    raise ASCError(f"{method} {path}\n{describe_errors(resp)}")
                wait = float(resp.headers.get("Retry-After") or delay)
                print(f"  {resp.status_code} from {method} {path}, retrying in {wait:.0f}s", file=sys.stderr)
                time.sleep(wait)
                delay *= 2
                continue
            if resp.status_code >= 400:
                raise ASCError(f"{method} {path}\n{describe_errors(resp)}")
            return resp.json() if resp.content else {}
        raise ASCError(f"{method} {path}: gave up")

    def get(self, path: str, **params) -> dict:
        return self.request("GET", path, params=params or None)

    def get_all(self, path: str, **params) -> list[dict]:
        """Follows links.next and returns every item of a collection."""
        params.setdefault("limit", 200)
        out = self.get(path, **params)
        items = list(out.get("data", []))
        nxt = out.get("links", {}).get("next")
        while nxt:
            out = self.request("GET", nxt)
            items.extend(out.get("data", []))
            nxt = out.get("links", {}).get("next")
        return items

    def write(self, method: str, path: str, body: dict | None, summary: str) -> dict:
        """A write. Dry run prints it and returns a placeholder resource."""
        with self._lock:
            self.writes += 1
            self._fake += 1
            fake = self._fake
        if not self.apply:
            print(f"  would {summary}")
            data_type = (body or {}).get("data", {}).get("type", "resource") if isinstance((body or {}).get("data"), dict) else "resource"
            return {"data": {"id": f"(new-{fake})", "type": data_type, "attributes": {}}}
        print(f"  {summary}")
        return self.request(method, path, body=body)


def is_placeholder(resource_id: str) -> bool:
    return resource_id.startswith("(new-")


# ---------------------------------------------------------------- uploads


def md5(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def upload_asset(api: Client, create_path: str, body: dict, file: Path, patch_type: str, checksum: bool) -> str:
    """Reserve an asset, PUT its bytes to the upload operations, then commit it.

    https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect
    """
    reservation = api.write("POST", create_path, body, f"upload {file.name} ({file.stat().st_size} bytes)")
    asset = reservation["data"]
    if not api.apply:
        return asset["id"]
    data = file.read_bytes()
    for op in asset["attributes"].get("uploadOperations") or []:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        for attempt in range(5):
            try:
                resp = requests.request(op["method"], op["url"], data=chunk, headers=headers, timeout=120)
            except (requests.ConnectionError, requests.Timeout) as exc:
                if attempt == 4:
                    raise ASCError(f"upload of {file.name} failed: {exc}") from exc
                time.sleep(2 ** attempt)
                continue
            if resp.status_code < 400:
                break
            if attempt == 4 or (resp.status_code < 500 and resp.status_code != 429):
                raise ASCError(f"upload of {file.name} failed: HTTP {resp.status_code} {resp.text[:300]}")
            time.sleep(2 ** attempt)
    attrs: dict[str, Any] = {"uploaded": True}
    if checksum:
        attrs["sourceFileChecksum"] = md5(file)
    api.request("PATCH", f"{create_path}/{asset['id']}", body={"data": {"type": patch_type, "id": asset["id"], "attributes": attrs}})
    return asset["id"]


UPLOAD_WORKERS = 6


def upload_assets(api: Client, create_path: str, jobs: list[tuple[dict, Path]], patch_type: str, checksum: bool) -> list[str]:
    """Uploads several files at once, then waits for Apple to process them
    together. Returns the asset ids in the order of `jobs`."""
    if not jobs:
        return []
    with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as pool:
        ids = list(pool.map(lambda job: upload_asset(api, create_path, job[0], job[1], patch_type, checksum), jobs))
    if api.apply:
        wait_for_assets(api, create_path, [(i, path.name) for i, (_, path) in zip(ids, jobs)])
    return ids


def wait_for_assets(api: Client, create_path: str, assets: list[tuple[str, str]], timeout: float = 90) -> None:
    """Polls until Apple has processed every asset, so a rejected file shows up here."""
    pending = dict(assets)
    deadline = time.time() + timeout
    while pending and time.time() < deadline:
        with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as pool:
            states = dict(zip(pending, pool.map(
                lambda i: api.get(f"{create_path}/{i}")["data"]["attributes"].get("assetDeliveryState") or {}, pending)))
        for asset_id, state in states.items():
            if state.get("state") == "FAILED":
                raise ASCError(f"Apple rejected {pending[asset_id]}: {json.dumps(state.get('errors'))}")
            if state.get("state") == "COMPLETE":
                del pending[asset_id]
        if pending:
            time.sleep(3)
    for name in pending.values():
        print(f"  {name} is still processing; check App Store Connect later")


def ensure_screenshot_branch() -> Path:
    """The screenshots branch, downloaded and laid out by scripts/appstore_screenshots.sh."""
    if not (SCREENSHOTS_DIR / "framed").is_dir():
        import subprocess

        print(f"Downloading the screenshots branch with {SCREENSHOTS_SCRIPT.relative_to(ROOT)}")
        subprocess.run([str(SCREENSHOTS_SCRIPT)], check=True, stdout=subprocess.DEVNULL)
    return SCREENSHOTS_DIR


# ---------------------------------------------------------------- app lookup


def find_app(api: Client) -> dict:
    apps = api.get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID, "fields[apps]": "name,bundleId,primaryLocale"}).get("data", [])
    apps = [a for a in apps if a["attributes"].get("bundleId") == BUNDLE_ID]
    if not apps:
        raise ASCError(f"No app with bundle id {BUNDLE_ID} is visible to this API key")
    return apps[0]


def store_locales(api: Client, app: dict | None) -> list[str]:
    """The listing's localisations in App Store Connect, primary first. Without
    credentials, the metadata folders stand in."""
    if app is None:
        found = sorted(p.name for p in (ROOT / "ios/AppStore/metadata").iterdir() if p.is_dir())
        return list(dict.fromkeys([LOCALE, *found]))
    primary = app["attributes"].get("primaryLocale") or LOCALE
    found = set()
    for info in api.get_all(f"/v1/apps/{app['id']}/appInfos"):
        found.update(l["attributes"]["locale"] for l in api.get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations"))
    return [primary, *sorted(found - {primary})]


# ---------------------------------------------------------------- status


def cmd_status(api: Client, args) -> int:
    if not api.online:
        raise ASCError("status needs ASC_KEY_ID, ASC_ISSUER_ID and the key file")
    app = find_app(api)
    out = api.get(
        "/v1/builds",
        **{
            "filter[app]": app["id"],
            "sort": "-uploadedDate",
            "limit": 5,
            "include": "preReleaseVersion,buildBetaDetail",
            "fields[builds]": "version,uploadedDate,processingState,expired,preReleaseVersion,buildBetaDetail",
            "fields[preReleaseVersions]": "version",
            "fields[buildBetaDetails]": "internalBuildState,externalBuildState",
        },
    )
    included = {(i["type"], i["id"]): i["attributes"] for i in out.get("included", [])}
    print(f"{app['attributes']['name']} ({BUNDLE_ID}), app id {app['id']}\n")
    rows = [("Version", "Build", "Processing", "Uploaded", "Internal beta", "External beta")]
    for b in out.get("data", []):
        a = b["attributes"]
        rel = b.get("relationships", {})
        pre = included.get(("preReleaseVersions", (rel.get("preReleaseVersion", {}).get("data") or {}).get("id")), {})
        beta = included.get(("buildBetaDetails", (rel.get("buildBetaDetail", {}).get("data") or {}).get("id")), {})
        uploaded = a.get("uploadedDate", "")
        if uploaded:
            uploaded = dt.datetime.fromisoformat(uploaded).astimezone().strftime("%Y-%m-%d %H:%M")
        state = a.get("processingState", "")
        if a.get("expired"):
            state += " (expired)"
        rows.append((pre.get("version", "?"), a.get("version", "?"), state, uploaded,
                     beta.get("internalBuildState", "-"), beta.get("externalBuildState", "-")))
    widths = [max(len(str(r[i])) for r in rows) for i in range(len(rows[0]))]
    for r in rows:
        print("  ".join(str(c).ljust(w) for c, w in zip(r, widths)).rstrip())
    if len(rows) == 1:
        print("No builds.")
    return 0


# ---------------------------------------------------------------- events


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


def enum_value(raw: str, allowed: set[str] | dict[str, str], what: str, folder: str) -> str:
    if isinstance(allowed, dict):
        value = allowed.get(raw.strip().lower())
    else:
        value = raw.strip().upper().replace(" ", "_")
        value = value if value in allowed else None
    if not value:
        options = sorted(allowed.values()) if isinstance(allowed, dict) else sorted(allowed)
        raise ASCError(f"{folder}/event.json: unknown {what} {raw!r}; expected one of {', '.join(options)}")
    return value


def iso(day: dt.date, end: bool = False) -> str:
    return f"{day.isoformat()}T{'23:59:00' if end else '00:00:00'}.000Z"


def compute_schedule(schedule: dict, start: dt.date, folder: str) -> tuple[dt.date, dt.date, dt.date]:
    """(publish, eventStart, eventEnd) from the folder's rule and --start."""
    rule = schedule.get("rule")
    lead = int(schedule.get("publish_days_before", 0))
    if rule == "release":
        begin = start
        finish = begin + dt.timedelta(days=int(schedule["duration_days"]) - 1)
    elif rule == "month":
        begin = start if start.day == 1 else (start.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
        finish = begin.replace(day=calendar.monthrange(begin.year, begin.month)[1])
    elif rule == "fixed":
        sm, sd = (int(x) for x in schedule["start"].split("-"))
        em, ed = (int(x) for x in schedule["end"].split("-"))
        begin = dt.date(start.year, sm, sd)
        if begin < start:
            begin = dt.date(start.year + 1, sm, sd)
        finish = dt.date(begin.year + (1 if (em, ed) < (sm, sd) else 0), em, ed)
    else:
        raise ASCError(f"{folder}/event.json: schedule.rule must be release, month or fixed")
    publish = begin - dt.timedelta(days=lead)
    days = (finish - begin).days + 1
    if days > MAX_EVENT_DAYS:
        raise ASCError(f"{folder}: event runs {days} days; Apple allows {MAX_EVENT_DAYS}")
    if lead > MAX_PUBLISH_LEAD_DAYS:
        raise ASCError(f"{folder}: publishes {lead} days early; Apple allows {MAX_PUBLISH_LEAD_DAYS}")
    return publish, begin, finish


@dataclass
class EventSpec:
    folder: Path
    reference_name: str
    attributes: dict
    localization: dict
    media: dict[str, Path | None] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)


def load_events(start: dt.date, all_territories: list[str] | None, media_dir: Path | None,
                primary_locale: str = LOCALE) -> list[EventSpec]:
    specs = []
    for folder in sorted(p for p in EVENTS_DIR.iterdir() if (p / "event.json").is_file()):
        name = folder.name
        raw = json.loads((folder / "event.json").read_text(encoding="utf-8"))
        publish, begin, finish = compute_schedule(raw.get("schedule", {}), start, name)
        warnings = []
        if publish < dt.date.today():
            warnings.append(f"publish date {publish} is in the past; pass a later --start")
        territories = raw.get("territories", "all")
        if territories == "all":
            codes = list(all_territories or ["(every territory)"])
        elif isinstance(territories, list):
            codes = [t.upper() for t in territories]
            if all_territories is not None:
                unknown = [c for c in codes if c not in all_territories]
                if unknown:
                    warnings.append(f"not App Store territories, left out: {', '.join(unknown)}")
                codes = [c for c in codes if c in all_territories]
        else:
            raise ASCError(f"{name}/event.json: territories must be \"all\" or a list of ISO 3166-1 alpha-3 codes")
        attributes = {
            "referenceName": raw["reference_name"],
            "badge": enum_value(raw["badge"], BADGES, "badge", name),
            "purpose": enum_value(raw["purpose"], PURPOSES, "purpose", name),
            "priority": enum_value(raw["priority"], PRIORITIES, "priority", name),
            "deepLink": raw.get("deep_link") or None,
            "primaryLocale": primary_locale,
            "territorySchedules": [{
                "territories": sorted(codes),
                "publishStart": iso(publish),
                "eventStart": iso(begin),
                "eventEnd": iso(finish, end=True),
            }],
        }
        localization = {
            "name": read_text(folder / "name.txt"),
            "shortDescription": read_text(folder / "short_description.txt"),
            "longDescription": read_text(folder / "long_description.txt"),
        }
        for key, limit in (("name", 30), ("shortDescription", 50), ("longDescription", 120)):
            if len(localization[key]) > limit:
                raise ASCError(f"{name}: {key} is {len(localization[key])} characters; the limit is {limit}")
        media = {}
        for asset_type, filename in EVENT_MEDIA.items():
            path = media_dir / "events" / name / filename if media_dir else None
            media[asset_type] = path if path and path.is_file() else None
            if media[asset_type] is None:
                warnings.append(f"{filename} is not in {media_dir / 'events' / name if media_dir else 'the art folder'}")
        specs.append(EventSpec(folder, raw["reference_name"], attributes, localization, media, warnings))
    return specs


def normalize_schedules(schedules: list[dict] | None) -> list[dict]:
    def norm_time(value: str | None) -> str:
        if not value:
            return ""
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M")

    return sorted(
        ({"territories": sorted(s.get("territories") or []), "publishStart": norm_time(s.get("publishStart")),
          "eventStart": norm_time(s.get("eventStart")), "eventEnd": norm_time(s.get("eventEnd"))} for s in schedules or []),
        key=lambda s: s["eventStart"],
    )


def diff_fields(current: dict, wanted: dict) -> dict:
    changes = {}
    for key, value in wanted.items():
        if key == "territorySchedules":
            if normalize_schedules(current.get(key)) != normalize_schedules(value):
                changes[key] = value
        elif (current.get(key) or None) != (value or None):
            changes[key] = value
    return changes


def show_value(key: str, value: Any) -> str:
    if key == "territorySchedules":
        parts = []
        for s in value or []:
            n = len(s.get("territories") or [])
            terr = ", ".join(s["territories"]) if n <= 25 else f"{n} territories"
            parts.append(f"publish {s.get('publishStart', '')[:10]}, runs {s.get('eventStart', '')[:10]} to {s.get('eventEnd', '')[:10]}, {terr}")
        return "; ".join(parts) or "none"
    return json.dumps(value, ensure_ascii=False)


def cmd_events(api: Client, args) -> int:
    start = args.start or dt.date.today()
    media_dir = args.art or ensure_screenshot_branch()
    app = find_app(api) if api.online else None
    all_territories = sorted(t["id"] for t in api.get_all("/v1/territories")) if api.online else None
    locales = store_locales(api, app)
    specs = load_events(start, all_territories, media_dir, locales[0])

    existing = {}
    if app:
        for ev in api.get_all(f"/v1/apps/{app['id']}/appEvents"):
            existing[ev["attributes"]["referenceName"]] = ev
    else:
        print("No credentials: showing everything as new without reading App Store Connect.\n")

    for spec in specs:
        print(f"{spec.folder.name}: {spec.reference_name!r}")
        for w in spec.warnings:
            print(f"  warning: {w}")
        current = existing.get(spec.reference_name)
        if current is None and args.images_only:
            print("  not in App Store Connect yet; skipped (run without --images-only to create it)\n")
            continue
        if current is None:
            created = api.write(
                "POST", "/v1/appEvents",
                {"data": {"type": "appEvents", "attributes": spec.attributes,
                          "relationships": {"app": {"data": {"type": "apps", "id": app["id"] if app else "(app)"}}}}},
                "create the event: " + ", ".join(f"{k} {show_value(k, v)}" for k, v in spec.attributes.items()),
            )
            event_id = created["data"]["id"]
        else:
            event_id = current["id"]
            state = current["attributes"].get("eventState")
            print(f"  exists ({event_id}, {state})")
            changes = diff_fields(current["attributes"], spec.attributes)
            if state != "DRAFT":
                # Past draft, Apple only takes schedule and priority changes.
                locked = {k: v for k, v in changes.items() if k not in EDITABLE_AFTER_DRAFT}
                for key, value in locked.items():
                    print(f"  warning: {key} is locked while the event is {state}; "
                          f"it stays {show_value(key, current['attributes'].get(key))}, not {show_value(key, value)}")
                changes = {k: v for k, v in changes.items() if k in EDITABLE_AFTER_DRAFT}
            if changes and not args.images_only:
                api.write(
                    "PATCH", f"/v1/appEvents/{event_id}",
                    {"data": {"type": "appEvents", "id": event_id, "attributes": changes}},
                    "update the event: " + "; ".join(
                        f"{k} {show_value(k, current['attributes'].get(k))} -> {show_value(k, v)}" for k, v in changes.items()),
                )

        for locale in locales:
            sync_event_locale(api, event_id, spec, locale, args.images_only)
        print()

    finish(api, "events")
    return 0


def sync_event_locale(api: Client, event_id: str, spec: "EventSpec", locale: str, images_only: bool = False) -> None:
    print(f"  {locale}:")
    loc = None
    if not is_placeholder(event_id) and api.online:
        loc = next((l for l in api.get_all(f"/v1/appEvents/{event_id}/localizations") if l["attributes"]["locale"] == locale), None)
    if loc is None and images_only:
        print("    no text for this locale yet; skipped")
        return
    if loc is None:
        created = api.write(
            "POST", "/v1/appEventLocalizations",
            {"data": {"type": "appEventLocalizations", "attributes": {"locale": locale, **spec.localization},
                      "relationships": {"appEvent": {"data": {"type": "appEvents", "id": event_id}}}}},
            f"add the {locale} text: " + ", ".join(f"{k} {json.dumps(v, ensure_ascii=False)}" for k, v in spec.localization.items()),
        )
        loc_id = created["data"]["id"]
    else:
        loc_id = loc["id"]
        changes = {k: v for k, v in spec.localization.items() if (loc["attributes"].get(k) or "") != v}
        if changes and not images_only:
            api.write(
                "PATCH", f"/v1/appEventLocalizations/{loc_id}",
                {"data": {"type": "appEventLocalizations", "id": loc_id, "attributes": changes}},
                f"update the {locale} text: " + "; ".join(
                    f"{k} {json.dumps(loc['attributes'].get(k), ensure_ascii=False)} -> {json.dumps(v, ensure_ascii=False)}" for k, v in changes.items()),
            )

    # Event card and details image
    shots = []
    if not is_placeholder(loc_id) and api.online:
        shots = api.get_all(f"/v1/appEventLocalizations/{loc_id}/appEventScreenshots")
    jobs = []
    for asset_type, path in spec.media.items():
        if path is None:
            continue
        have = [s for s in shots if s["attributes"].get("appEventAssetType") == asset_type]
        same = [s for s in have if s["attributes"].get("fileName") == path.name
                and s["attributes"].get("fileSize") == path.stat().st_size
                and (s["attributes"].get("assetDeliveryState") or {}).get("state") == "COMPLETE"]
        if same and len(have) == 1:
            continue
        for old in have:
            api.write("DELETE", f"/v1/appEventScreenshots/{old['id']}", None,
                      f"remove the old {asset_type} {old['attributes'].get('fileName')}")
        jobs.append((
            {"data": {"type": "appEventScreenshots",
                      "attributes": {"fileName": path.name, "fileSize": path.stat().st_size, "appEventAssetType": asset_type},
                      "relationships": {"appEventLocalization": {"data": {"type": "appEventLocalizations", "id": loc_id}}}}},
            path,
        ))
    upload_assets(api, "/v1/appEventScreenshots", jobs, "appEventScreenshots", checksum=False)


# ---------------------------------------------------------------- custom product pages


@dataclass
class PageSpec:
    folder: Path
    name: str
    promotional_text: str
    screenshots: list[Path]
    keywords: list[str]
    warnings: list[str] = field(default_factory=list)


def load_pages(shots_dir: Path) -> list[PageSpec]:
    specs = []
    for folder in sorted(p for p in PAGES_DIR.iterdir() if p.is_dir()):
        warnings = []
        name = read_text(folder / "name.txt") or folder.name
        promo = read_text(folder / "promotional_text.txt")
        if len(promo) > 170:
            raise ASCError(f"{folder.name}: promotional text is {len(promo)} characters; the limit is 170")
        shots = []
        for stem in read_text(folder / "screenshots.txt").split():
            path = shots_dir / f"{stem}.png"
            if path.is_file():
                shots.append(path)
            else:
                warnings.append(f"{stem}.png is not in {shots_dir}")
        keywords = [k.strip() for k in read_text(folder / "keywords.txt").split(",") if k.strip()]
        specs.append(PageSpec(folder, name, promo, shots, keywords, warnings))
    return specs


def cmd_pages(api: Client, args) -> int:
    # The composed store art (scripts/store_art.py) when --art names it,
    # else the framed captures on the screenshots branch.
    shots_dir = args.art / "6.9" if args.art else ensure_screenshot_branch() / "framed"
    specs = load_pages(shots_dir)
    app = find_app(api) if api.online else None
    existing = {}
    # A new page must start in the app's primary locale; the others are added beside it.
    locales = store_locales(api, app)
    primary = locales[0]
    available_keywords: dict[str, dict[str, str] | None] = {locale: None for locale in locales}
    if app:
        for page in api.get_all(f"/v1/apps/{app['id']}/appCustomProductPages"):
            existing[page["attributes"]["name"]] = page
        # Pages can only use keywords from the latest approved version's keyword field.
        for locale in locales:
            kw = api.get_all(f"/v1/apps/{app['id']}/searchKeywords", **{"filter[locale]": locale, "filter[platform]": "IOS"})
            available_keywords[locale] = {k["id"].strip().lower(): k["id"] for k in kw}
    else:
        print("No credentials: showing everything as new without reading App Store Connect.\n")

    for spec in specs:
        print(f"{spec.folder.name}: {spec.name!r}")
        for w in spec.warnings:
            print(f"  warning: {w}")
        page = existing.get(spec.name)
        version_id = None
        if page is None and args.images_only:
            print("  not in App Store Connect yet; skipped (run without --images-only to create it)\n")
            continue
        if page is None:
            version_ref = "${new-appCustomProductPageVersion-id}"
            loc_ref = "${new-appCustomProductPageLocalization-id}"
            created = api.write(
                "POST", "/v1/appCustomProductPages",
                {"data": {"type": "appCustomProductPages", "attributes": {"name": spec.name},
                          "relationships": {"app": {"data": {"type": "apps", "id": app["id"] if app else "(app)"}},
                                            "appCustomProductPageVersions": {"data": [{"type": "appCustomProductPageVersions", "id": version_ref}]}}},
                 "included": [
                     {"type": "appCustomProductPageVersions", "id": version_ref,
                      "relationships": {"appCustomProductPageLocalizations": {"data": [{"type": "appCustomProductPageLocalizations", "id": loc_ref}]}}},
                     {"type": "appCustomProductPageLocalizations", "id": loc_ref,
                      "attributes": {"locale": primary, "promotionalText": spec.promotional_text}},
                 ]},
                f"create the page with {primary} promotional text {json.dumps(spec.promotional_text, ensure_ascii=False)}",
            )
            page_id = created["data"]["id"]
        else:
            page_id = page["id"]
            print(f"  exists ({page_id}), {page['attributes'].get('url') or 'no url yet'}")

        if not is_placeholder(page_id) and api.online:
            versions = api.get_all(f"/v1/appCustomProductPages/{page_id}/appCustomProductPageVersions")
            editable = [v for v in versions if v["attributes"].get("state") in EDITABLE_PAGE_STATES]
            pending = [v for v in versions if v["attributes"].get("state") in {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"}]
            if editable:
                version_id = editable[0]["id"]
            elif pending:
                print(f"  version {pending[0]['attributes'].get('version')} is {pending[0]['attributes']['state']}; skipping until review finishes\n")
                continue
            else:
                created = api.write(
                    "POST", "/v1/appCustomProductPageVersions",
                    {"data": {"type": "appCustomProductPageVersions",
                              "relationships": {"appCustomProductPage": {"data": {"type": "appCustomProductPages", "id": page_id}}}}},
                    "start a new page version (the current one is approved)",
                )
                version_id = created["data"]["id"]

        locs = []
        if version_id and not is_placeholder(version_id):
            locs = api.get_all(f"/v1/appCustomProductPageVersions/{version_id}/appCustomProductPageLocalizations")
        for locale in locales:
            print(f"  {locale}:")
            loc = next((l for l in locs if l["attributes"]["locale"] == locale), None)
            if loc is not None:
                loc_id = loc["id"]
                if (loc["attributes"].get("promotionalText") or "") != spec.promotional_text and not args.images_only:
                    api.write(
                        "PATCH", f"/v1/appCustomProductPageLocalizations/{loc_id}",
                        {"data": {"type": "appCustomProductPageLocalizations", "id": loc_id,
                                  "attributes": {"promotionalText": spec.promotional_text}}},
                        f"update {locale} promotional text {json.dumps(loc['attributes'].get('promotionalText'), ensure_ascii=False)} -> {json.dumps(spec.promotional_text, ensure_ascii=False)}",
                    )
            elif args.images_only:
                print("    no text for this locale yet; skipped")
                continue
            elif page is None and locale == primary and is_placeholder(page_id):
                # Dry run: the create request above makes this one.
                loc_id = "(new-localization)"
            else:
                created = api.write(
                    "POST", "/v1/appCustomProductPageLocalizations",
                    {"data": {"type": "appCustomProductPageLocalizations",
                              "attributes": {"locale": locale, "promotionalText": spec.promotional_text},
                              "relationships": {"appCustomProductPageVersion": {"data": {"type": "appCustomProductPageVersions", "id": version_id or "(version)"}}}}},
                    f"add {locale} with promotional text {json.dumps(spec.promotional_text, ensure_ascii=False)}",
                )
                loc_id = created["data"]["id"]
            sync_page_screenshots(api, loc_id, spec)
            if not args.images_only:
                sync_page_keywords(api, loc_id, spec, available_keywords[locale], locale)

        if not is_placeholder(page_id):
            hint = "  (paste into customPageId in docs/open.html)" if spec.folder.name == "crew-invite" else ""
            print(f"  page id {page_id}{hint}")
        print()

    finish(api, "pages")
    return 0


def sync_page_screenshots(api: Client, loc_id: str, spec: PageSpec) -> None:
    sets = []
    if not is_placeholder(loc_id) and api.online:
        sets = api.get_all(f"/v1/appCustomProductPageLocalizations/{loc_id}/appScreenshotSets")
    phone = next((s for s in sets if s["attributes"].get("screenshotDisplayType") == PHONE_DISPLAY_TYPE), None)
    current = []
    if phone:
        set_id = phone["id"]
        current = api.get_all(f"/v1/appScreenshotSets/{set_id}/appScreenshots")
        have = [(s["attributes"].get("fileName"), s["attributes"].get("sourceFileChecksum")) for s in current]
        want = [(p.name, md5(p)) for p in spec.screenshots]
        if have == want:
            return
    else:
        if not spec.screenshots:
            return
        created = api.write(
            "POST", "/v1/appScreenshotSets",
            {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": PHONE_DISPLAY_TYPE},
                      "relationships": {"appCustomProductPageLocalization": {"data": {"type": "appCustomProductPageLocalizations", "id": loc_id}}}}},
            f"add a {PHONE_DISPLAY_TYPE} (6.9-inch) screenshot set",
        )
        set_id = created["data"]["id"]
    print(f"  screenshots: {' '.join(p.stem for p in spec.screenshots)}"
          + (f" (replacing {' '.join(s['attributes'].get('fileName', '?') for s in current)})" if current else ""))
    with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as pool:
        list(pool.map(lambda old: api.write("DELETE", f"/v1/appScreenshots/{old['id']}", None,
                                            f"remove {old['attributes'].get('fileName')}"), current))
    ids = upload_assets(api, "/v1/appScreenshots", [
        ({"data": {"type": "appScreenshots", "attributes": {"fileName": path.name, "fileSize": path.stat().st_size},
                   "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}},
         path)
        for path in spec.screenshots
    ], "appScreenshots", checksum=True)
    if ids:
        api.write(
            "PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
            {"data": [{"type": "appScreenshots", "id": i} for i in ids]},
            "set the screenshot order to match screenshots.txt",
        )


def sync_page_keywords(api: Client, loc_id: str, spec: PageSpec, available: dict[str, str] | None,
                       locale: str = LOCALE) -> None:
    if not spec.keywords:
        return
    if available is None:
        api.writes += 1
        print(f"  would assign keywords: {', '.join(spec.keywords)} (not checked against the approved keyword list)")
        return
    usable = [available[k.lower()] for k in spec.keywords if k.lower() in available]
    missing = [k for k in spec.keywords if k.lower() not in available]
    if missing:
        print(f"  note: not in the latest approved version's {locale} keywords, so Apple will not accept them yet: {', '.join(missing)}")
    current = []
    if not is_placeholder(loc_id) and api.online:
        current = [k["id"] for k in api.get_all(f"/v1/appCustomProductPageLocalizations/{loc_id}/relationships/searchKeywords")]
    add = [k for k in usable if k not in current]
    remove = [k for k in current if k not in usable]
    if add:
        api.write("POST", f"/v1/appCustomProductPageLocalizations/{loc_id}/relationships/searchKeywords",
                  {"data": [{"type": "appKeywords", "id": k} for k in add]}, f"assign keywords: {', '.join(add)}")
    if remove:
        api.write("DELETE", f"/v1/appCustomProductPageLocalizations/{loc_id}/relationships/searchKeywords",
                  {"data": [{"type": "appKeywords", "id": k} for k in remove]}, f"unassign keywords: {', '.join(remove)}")


# ---------------------------------------------------------------- Game Center


# A version in one of these states takes text and image changes. A live one
# gets a new version; one in review is left alone.
EDITABLE_GC_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED"}
LIVE_GC_STATES = {"LIVE", "REPLACED_WITH_NEW_VERSION"}
GC_FORMATTERS = {"INTEGER", "DECIMAL_POINT_1_PLACE", "DECIMAL_POINT_2_PLACE", "DECIMAL_POINT_3_PLACE"}
EDITABLE_APP_VERSION_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}


@dataclass(frozen=True)
class GCKind:
    """The resources behind one kind of Game Center item. Achievements and
    leaderboards use the versioned v2 API; challenges only exist in v1."""
    label: str
    type: str
    create: str
    listing: str
    version_type: str
    version_create: str
    versions: str
    version_rel: str
    loc_type: str
    loc_create: str
    locs: str
    image_type: str
    image_create: str
    # Achievement and leaderboard images hang off each localization, a
    # challenge's default image off its version.
    image_on_version: bool = False
    image_of_version: str = ""


ACHIEVEMENTS = GCKind(
    "achievement", "gameCenterAchievements", "/v2/gameCenterAchievements",
    "/v1/gameCenterDetails/{id}/gameCenterAchievementsV2",
    "gameCenterAchievementVersions", "/v2/gameCenterAchievementVersions", "/v2/gameCenterAchievements/{id}/versions",
    "achievement", "gameCenterAchievementLocalizations", "/v2/gameCenterAchievementLocalizations",
    "/v2/gameCenterAchievementVersions/{id}/localizations",
    "gameCenterAchievementImages", "/v2/gameCenterAchievementImages",
)
LEADERBOARDS = GCKind(
    "leaderboard", "gameCenterLeaderboards", "/v2/gameCenterLeaderboards",
    "/v1/gameCenterDetails/{id}/gameCenterLeaderboardsV2",
    "gameCenterLeaderboardVersions", "/v2/gameCenterLeaderboardVersions", "/v2/gameCenterLeaderboards/{id}/versions",
    "leaderboard", "gameCenterLeaderboardLocalizations", "/v2/gameCenterLeaderboardLocalizations",
    "/v2/gameCenterLeaderboardVersions/{id}/localizations",
    "gameCenterLeaderboardImages", "/v2/gameCenterLeaderboardImages",
)
CHALLENGES = GCKind(
    "challenge", "gameCenterChallenges", "/v1/gameCenterChallenges",
    "/v1/gameCenterDetails/{id}/gameCenterChallenges",
    "gameCenterChallengeVersions", "/v1/gameCenterChallengeVersions", "/v1/gameCenterChallenges/{id}/versions",
    "challenge", "gameCenterChallengeLocalizations", "/v1/gameCenterChallengeLocalizations",
    "/v1/gameCenterChallengeVersions/{id}/localizations",
    "gameCenterChallengeImages", "/v1/gameCenterChallengeImages",
    image_on_version=True, image_of_version="/v1/gameCenterChallengeVersions/{id}/defaultImage",
)


@dataclass
class GCItem:
    folder: Path
    vendor: str
    # Sent when the item is created, then compared with App Store Connect.
    attributes: dict
    # Attributes App Store Connect fixes at creation (the vendor id, a
    # challenge's type).
    create_only: dict
    localization: dict
    image: Path
    leaderboard: str = ""


@dataclass
class GCState:
    """What App Store Connect holds for one item."""
    item: dict | None = None
    version: dict | None = None
    versions: list[dict] = field(default_factory=list)
    locs: list[dict] = field(default_factory=list)
    images: dict[str, dict] = field(default_factory=dict)
    version_image: dict | None = None


def get_optional(api: Client, path: str, **params) -> dict | None:
    """A to-one relationship, or None when there is nothing behind it."""
    try:
        return api.get(path, **params).get("data")
    except ASCError as exc:
        if "HTTP 404" in str(exc):
            return None
        raise


def load_gc_json(folder: Path, filename: str, required: tuple[str, ...]) -> dict:
    raw = json.loads((folder / filename).read_text(encoding="utf-8"))
    missing = [k for k in required if not raw.get(k) and raw.get(k) is not False]
    if missing:
        raise ASCError(f"{folder.name}/{filename}: missing {', '.join(missing)}")
    if not (folder / "image.png").is_file():
        raise ASCError(f"{folder.name}: no image.png; run uv run scripts/render_achievement_art.py")
    return raw


def check_length(folder: Path, key: str, value: str, limit: int) -> None:
    if len(value) > limit:
        raise ASCError(f"{folder.name}: {key} is {len(value)} characters; the limit is {limit}")


def load_achievements() -> list[GCItem]:
    items = []
    for folder in sorted(p for p in (GAMECENTER_DIR / "achievements").iterdir() if p.is_dir()):
        raw = load_gc_json(folder, "achievement.json", ("reference_name", "vendor_identifier", "points", "name",
                                                         "before_earned_description", "after_earned_description"))
        if not 1 <= int(raw["points"]) <= 100:
            raise ASCError(f"{folder.name}: points must be 1 to 100")
        loc = {"name": raw["name"], "beforeEarnedDescription": raw["before_earned_description"],
               "afterEarnedDescription": raw["after_earned_description"]}
        check_length(folder, "name", loc["name"], 30)
        for key in ("beforeEarnedDescription", "afterEarnedDescription"):
            check_length(folder, key, loc[key], 200)
        items.append(GCItem(
            folder, raw["vendor_identifier"],
            {"referenceName": raw["reference_name"], "points": int(raw["points"]),
             "showBeforeEarned": bool(raw.get("show_before_earned", True)),
             "repeatable": bool(raw.get("repeatable", False))},
            {"vendorIdentifier": raw["vendor_identifier"]},
            loc, folder / "image.png"))
    total = sum(i.attributes["points"] for i in items)
    if total > 1000:
        raise ASCError(f"achievement points total {total}; Apple allows 1000")
    return items


def load_leaderboards() -> list[GCItem]:
    items = []
    for folder in sorted(p for p in (GAMECENTER_DIR / "leaderboards").iterdir() if p.is_dir()):
        raw = load_gc_json(folder, "leaderboard.json", ("reference_name", "vendor_identifier", "formatter", "name"))
        if raw["formatter"] not in GC_FORMATTERS:
            raise ASCError(f"{folder.name}: formatter must be one of {', '.join(sorted(GC_FORMATTERS))}")
        attributes = {
            "referenceName": raw["reference_name"],
            "defaultFormatter": raw["formatter"],
            "submissionType": raw.get("submission_type", "BEST_SCORE"),
            "scoreSortType": raw.get("sort", "DESC"),
        }
        recurrence = raw.get("recurrence")
        if recurrence:
            attributes.update({"recurrenceStartDate": recurrence["start"],
                               "recurrenceDuration": recurrence["duration"],
                               "recurrenceRule": recurrence["rule"]})
        loc = {"name": raw["name"], "description": raw.get("description", ""),
               "formatterSuffix": raw.get("suffix", ""), "formatterSuffixSingular": raw.get("suffix_singular", "")}
        check_length(folder, "name", loc["name"], 64)
        items.append(GCItem(folder, raw["vendor_identifier"], attributes,
                            {"vendorIdentifier": raw["vendor_identifier"]}, loc, folder / "image.png"))
    return items


def load_challenges() -> list[GCItem]:
    items = []
    for folder in sorted(p for p in (GAMECENTER_DIR / "challenges").iterdir() if p.is_dir()):
        raw = load_gc_json(folder, "challenge.json", ("reference_name", "vendor_identifier", "leaderboard", "name"))
        loc = {"name": raw["name"], "description": raw.get("description", "")}
        items.append(GCItem(folder, raw["vendor_identifier"],
                            {"referenceName": raw["reference_name"], "repeatable": bool(raw.get("repeatable", True))},
                            {"vendorIdentifier": raw["vendor_identifier"], "challengeType": "LEADERBOARD"},
                            loc, folder / "image.png", leaderboard=raw["leaderboard"]))
    return items


def same_value(key: str, current: Any, wanted: Any) -> bool:
    if key == "recurrenceStartDate" and current and wanted:
        parse = lambda v: dt.datetime.fromisoformat(v.replace("Z", "+00:00")).astimezone(dt.timezone.utc)  # noqa: E731
        return parse(current) == parse(wanted)
    return (current if current is not None else None) == (wanted if wanted != "" else None) or current == wanted


def read_gc_state(api: Client, kind: GCKind, item: dict | None) -> GCState:
    """Reads one item's versions, the editable version's localizations and
    their images. Runs on a worker thread."""
    state = GCState(item=item)
    if item is None or not api.online:
        return state
    state.versions = api.get_all(kind.versions.format(id=item["id"]))
    ordered = sorted(state.versions, key=lambda v: v["attributes"].get("version") or 0)
    if ordered:
        state.version = ordered[-1]
        vid = state.version["id"]
        out = api.get(kind.locs.format(id=vid), include="image", limit=50) if not kind.image_on_version \
            else api.get(kind.locs.format(id=vid), limit=50)
        state.locs = out.get("data", [])
        included = {i["id"]: i for i in out.get("included", [])}
        for loc in state.locs:
            ref = ((loc.get("relationships") or {}).get("image") or {}).get("data")
            if ref and ref["id"] in included:
                state.images[loc["id"]] = included[ref["id"]]
        if kind.image_on_version:
            state.version_image = get_optional(api, kind.image_of_version.format(id=vid))
    return state


def image_is_current(image: dict | None, path: Path) -> bool:
    if not image:
        return False
    a = image.get("attributes") or {}
    return (a.get("fileSize") == path.stat().st_size
            and (a.get("assetDeliveryState") or {}).get("state") in {"COMPLETE", "UPLOAD_COMPLETE"})


def sync_gc_items(api: Client, kind: GCKind, items: list[GCItem], detail_id: str, locales: list[str],
                  leaderboard_ids: dict[str, str] | None = None) -> dict[str, str]:
    """Creates or updates every item of one kind. Returns the ids by vendor id."""
    existing: dict[str, dict] = {}
    if api.online and not is_placeholder(detail_id):
        for found in api.get_all(kind.listing.format(id=detail_id)):
            existing[found["attributes"].get("vendorIdentifier")] = found
    with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as pool:
        states = list(pool.map(lambda i: read_gc_state(api, kind, existing.get(i.vendor)), items))

    ids: dict[str, str] = {}
    jobs: list[tuple[dict, Path]] = []
    for spec, state in zip(items, states):
        print(f"{kind.label} {spec.vendor}: {spec.localization['name']!r}")
        current = state.item
        if current is None:
            relationships: dict[str, Any] = {
                "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail_id}},
                "versions": {"data": [{"type": kind.version_type, "id": "${new-version}"}]},
            }
            if spec.leaderboard:
                board = (leaderboard_ids or {}).get(spec.leaderboard)
                if not board:
                    raise ASCError(f"{spec.folder.name}: no leaderboard {spec.leaderboard} in game-center/leaderboards")
                relationships["leaderboardV2"] = {"data": {"type": "gameCenterLeaderboards", "id": board}}
            created = api.write(
                "POST", kind.create,
                {"data": {"type": kind.type, "attributes": {**spec.create_only, **spec.attributes},
                          "relationships": relationships},
                 "included": [{"type": kind.version_type, "id": "${new-version}"}]},
                f"create the {kind.label}: " + ", ".join(f"{k} {json.dumps(v)}" for k, v in spec.attributes.items()),
            )
            item_id = created["data"]["id"]
            version_id = "(new-version)"
            if api.apply:
                versions = api.get_all(kind.versions.format(id=item_id))
                version_id = versions[0]["id"] if versions else version_id
        else:
            item_id = current["id"]
            attrs = current.get("attributes") or {}
            changes = {k: v for k, v in spec.attributes.items() if not same_value(k, attrs.get(k), v)}
            if attrs.get("archived"):
                print("  warning: archived in App Store Connect; left as is")
                changes = {}
            if changes:
                api.write(
                    "PATCH", f"{kind.create}/{item_id}",
                    {"data": {"type": kind.type, "id": item_id, "attributes": changes}},
                    f"update the {kind.label}: " + "; ".join(
                        f"{k} {json.dumps(attrs.get(k))} -> {json.dumps(v)}" for k, v in changes.items()),
                )
            version = state.version
            vstate = (version or {}).get("attributes", {}).get("state")
            if version is None or vstate in LIVE_GC_STATES:
                if version is not None and not gc_text_differs(spec, state, locales):
                    ids[spec.vendor] = item_id
                    print(f"  exists ({item_id}), version {version['attributes'].get('version')} {vstate}, up to date")
                    continue
                created = api.write(
                    "POST", kind.version_create,
                    {"data": {"type": kind.version_type,
                              "relationships": {kind.version_rel: {"data": {"type": kind.type, "id": item_id}}}}},
                    f"start a new {kind.label} version" + (f" (version {version['attributes'].get('version')} is {vstate})" if version else ""),
                )
                version_id = created["data"]["id"]
                state = GCState(item=current)
                if api.apply:
                    # A new version may start with the last one's text; read it
                    # so those localizations are updated, not added twice.
                    state = read_gc_state(api, kind, current)
            elif vstate not in EDITABLE_GC_STATES:
                print(f"  exists ({item_id}), version {version['attributes'].get('version')} is {vstate}; skipping until review finishes")
                ids[spec.vendor] = item_id
                continue
            else:
                version_id = version["id"]
                print(f"  exists ({item_id}), version {version['attributes'].get('version')} {vstate}")
        ids[spec.vendor] = item_id

        for locale in locales:
            loc = next((l for l in state.locs if l["attributes"].get("locale") == locale), None)
            if loc is None:
                created = api.write(
                    "POST", kind.loc_create,
                    {"data": {"type": kind.loc_type, "attributes": {"locale": locale, **spec.localization},
                              "relationships": {"version": {"data": {"type": kind.version_type, "id": version_id}}}}},
                    f"add {locale}: " + ", ".join(f"{k} {json.dumps(v, ensure_ascii=False)}" for k, v in spec.localization.items() if v),
                )
                loc_id = created["data"]["id"]
            else:
                loc_id = loc["id"]
                changes = {k: v for k, v in spec.localization.items() if (loc["attributes"].get(k) or "") != v}
                if changes:
                    api.write(
                        "PATCH", f"{kind.loc_create}/{loc_id}",
                        {"data": {"type": kind.loc_type, "id": loc_id, "attributes": changes}},
                        f"update {locale}: " + "; ".join(
                            f"{k} {json.dumps(loc['attributes'].get(k), ensure_ascii=False)} -> {json.dumps(v, ensure_ascii=False)}"
                            for k, v in changes.items()),
                    )
            if not kind.image_on_version:
                old = state.images.get(loc_id)
                if not image_is_current(old, spec.image):
                    if old:
                        api.write("DELETE", f"{kind.image_create}/{old['id']}", None,
                                  f"remove the old {locale} image {old['attributes'].get('fileName')}")
                    jobs.append(gc_image_job(kind, spec, "localization", kind.loc_type, loc_id))
        if kind.image_on_version and not image_is_current(state.version_image, spec.image):
            if state.version_image:
                api.write("DELETE", f"{kind.image_create}/{state.version_image['id']}", None, "remove the old image")
            jobs.append(gc_image_job(kind, spec, "version", kind.version_type, version_id))
    print(f"{len(jobs)} {kind.label} images to upload")
    upload_assets(api, kind.image_create, jobs, kind.image_type, checksum=False)
    print()
    return ids


def gc_text_differs(spec: GCItem, state: GCState, locales: list[str]) -> bool:
    """Whether a live version's text or image differs from the folder."""
    for locale in locales:
        loc = next((l for l in state.locs if l["attributes"].get("locale") == locale), None)
        if loc is None or any((loc["attributes"].get(k) or "") != v for k, v in spec.localization.items()):
            return True
        if not state.version_image and not image_is_current(state.images.get(loc["id"]), spec.image):
            return True
    if state.version_image is not None and not image_is_current(state.version_image, spec.image):
        return True
    return False


def gc_image_job(kind: GCKind, spec: GCItem, rel: str, rel_type: str, rel_id: str) -> tuple[dict, Path]:
    # Named after the item so App Store Connect lists recognisable files.
    name = f"{spec.vendor}.png"
    return ({"data": {"type": kind.image_type,
                      "attributes": {"fileName": name, "fileSize": spec.image.stat().st_size},
                      "relationships": {rel: {"data": {"type": rel_type, "id": rel_id}}}}},
            spec.image)


def ensure_game_center_capability(api: Client) -> None:
    """The App ID needs the Game Center capability for the entitlement to
    sign. It is on by default for App Store App IDs; this checks."""
    if not api.online:
        print("App ID: would check the Game Center capability\n")
        return
    try:
        bundles = api.get("/v1/bundleIds", **{"filter[identifier]": BUNDLE_ID, "include": "bundleIdCapabilities",
                                              "limit[bundleIdCapabilities]": 50})
    except ASCError as exc:
        print(f"App ID: could not read capabilities with this key ({str(exc).splitlines()[-1]}); "
              "check Game Center under Certificates, Identifiers & Profiles\n")
        return
    bundle = next((b for b in bundles.get("data", []) if b["attributes"].get("identifier") == BUNDLE_ID), None)
    if bundle is None:
        print(f"App ID: {BUNDLE_ID} not found; check Game Center under Certificates, Identifiers & Profiles\n")
        return
    # The identifier filter also matches the widget and watch App IDs, so
    # only the app's own capabilities count.
    mine = {c["id"] for c in ((bundle.get("relationships") or {}).get("bundleIdCapabilities") or {}).get("data") or []}
    caps = {i["attributes"].get("capabilityType") for i in bundles.get("included", [])
            if i["type"] == "bundleIdCapabilities" and i["id"] in mine}
    if "GAME_CENTER" in caps:
        print("App ID: Game Center capability is on\n")
        return
    api.write("POST", "/v1/bundleIdCapabilities",
              {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": "GAME_CENTER"},
                        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}}}}},
              "turn on the Game Center capability for the App ID")
    print()


def ensure_version_game_center(api: Client, app: dict) -> None:
    """Ticks Game Center on the version being prepared, if there is one, so
    the achievements and leaderboards can go to review with it."""
    versions = api.get_all(f"/v1/apps/{app['id']}/appStoreVersions", **{"filter[platform]": "IOS"})
    editable = [v for v in versions if v["attributes"].get("appVersionState") in EDITABLE_APP_VERSION_STATES
                or v["attributes"].get("appStoreState") in EDITABLE_APP_VERSION_STATES]
    if not editable:
        print("App version: none being prepared. Create the next version (1.3.1 or 1.4.0) in App Store Connect, "
              "run this again, then add the achievements and leaderboards to it before submitting.\n")
        return
    version = editable[0]
    label = version["attributes"].get("versionString")
    current = get_optional(api, f"/v1/appStoreVersions/{version['id']}/gameCenterAppVersion")
    if current is not None and (current.get("attributes") or {}).get("enabled") is not False:
        print(f"App version {label}: Game Center is on\n")
        return
    if current is None:
        api.write("POST", "/v1/gameCenterAppVersions",
                  {"data": {"type": "gameCenterAppVersions",
                            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}},
                  f"turn on Game Center for version {label}")
    else:
        api.write("PATCH", f"/v1/gameCenterAppVersions/{current['id']}",
                  {"data": {"type": "gameCenterAppVersions", "id": current["id"], "attributes": {"enabled": True}}},
                  f"turn on Game Center for version {label}")
    print()


def cmd_gamecenter(api: Client, args) -> int:
    achievements = load_achievements()
    leaderboards = load_leaderboards()
    challenges = load_challenges()
    app = find_app(api) if api.online else None
    locales = store_locales(api, app)
    if app is None:
        print("No credentials: showing everything as new without reading App Store Connect.\n")
    print(f"Locales: {', '.join(locales)}\n")

    ensure_game_center_capability(api)
    detail = get_optional(api, f"/v1/apps/{app['id']}/gameCenterDetail") if app else None
    if detail is None:
        created = api.write(
            "POST", "/v1/gameCenterDetails",
            {"data": {"type": "gameCenterDetails",
                      "relationships": {"app": {"data": {"type": "apps", "id": app["id"] if app else "(app)"}}}}},
            "turn on Game Center for the app",
        )
        detail_id = created["data"]["id"]
        print()
    else:
        detail_id = detail["id"]
        print(f"Game Center is on for the app ({detail_id})\n")
    if app:
        ensure_version_game_center(api, app)

    sync_gc_items(api, ACHIEVEMENTS, achievements, detail_id, locales)
    board_ids = sync_gc_items(api, LEADERBOARDS, leaderboards, detail_id, locales)
    sync_gc_items(api, CHALLENGES, challenges, detail_id, locales, board_ids)

    points = sum(i.attributes["points"] for i in achievements)
    print(f"{len(achievements)} achievements ({points} points), {len(leaderboards)} leaderboards, "
          f"{len(challenges)} challenges. Add them to the app version in App Store Connect and submit "
          "them with it; nothing here submits.")
    finish(api, "gamecenter")
    return 0


# ---------------------------------------------------------------- preview and creative art

MEDIA_DIR = ROOT / "ios" / "build" / "appstore-media"
PREVIEW_CONFIG = APPSTORE_DIR / "preview.json"
# Asset states from which an asset can be placed (processed, or further along in review).
PLACEABLE = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED", "APPROVED"}


@dataclass
class MediaJob:
    """One file placed in one placement group on every localisation of the version."""
    label: str
    placement_type: str
    group: str
    category: str
    file: Path
    video: bool
    poster: str | None = None


def media_jobs(args) -> list[MediaJob]:
    preview_poster = args.poster or (json.loads(PREVIEW_CONFIG.read_text()).get("poster") if PREVIEW_CONFIG.is_file() else None)
    header_video = args.header.suffix.lower() in {".mp4", ".mov"}
    return [
        MediaJob("app preview", "APP_PREVIEW", "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE", "APP_SCREENSHOTS_AND_PREVIEWS",
                 args.preview, True, preview_poster),
        MediaJob("header", "PRODUCT_PAGE_HEADER_ASSET", "DEFAULT_PROFILE", "CREATIVE_ASSETS", args.header, header_video,
                 args.header_poster if header_video else None),
        MediaJob("search results", "APP_STORE_SEARCH_RESULTS_ASSET", "DEFAULT_PROFILE", "CREATIVE_ASSETS", args.search, False),
    ]


def png_info(path: Path) -> dict:
    with path.open("rb") as fh:
        head = fh.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ASCError(f"{path.name} is not a PNG")
    width, height = struct.unpack(">II", head[16:24])
    return {"width": width, "height": height, "alpha": head[25] in (4, 6)}


def video_info(path: Path) -> dict | None:
    """Size, frame rate, duration and audio from ffprobe, or None without it."""
    if not shutil.which("ffprobe"):
        return None
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,width,height,avg_frame_rate:format=duration",
                          "-of", "json", str(path)], capture_output=True, text=True, check=True)
    probe = json.loads(out.stdout)
    picture = next(s for s in probe["streams"] if s["codec_type"] == "video")
    num, den = (int(n) for n in picture["avg_frame_rate"].split("/"))
    return {"width": picture["width"], "height": picture["height"], "fps": num / den,
            "duration": float(probe["format"]["duration"]),
            "audio": any(s["codec_type"] == "audio" for s in probe["streams"])}


def iso_seconds(value: str) -> float:
    match = re.fullmatch(r"PT(?:(\d+)M)?(?:([\d.]+)S)?", value)
    if not match:
        raise ASCError(f"unexpected duration {value!r} in the reference data")
    return int(match.group(1) or 0) * 60 + float(match.group(2) or 0)


def check_media(ref: dict, job: MediaJob) -> str:
    """Matches the file against the specs Apple lists for the job's placement
    group, so a wrong size fails here and not after a long upload. Returns
    the spec's short name."""
    types = {t["placementTypeId"]: t for t in ref["placementTypes"]}
    if job.placement_type not in types:
        raise ASCError(f"App Store Connect has no {job.placement_type} placements")
    mapping = next((m for m in types[job.placement_type].get("specMappings") or [] if m["placementGroupId"] == job.group), None)
    if mapping is None:
        raise ASCError(f"{job.group} is not a placement group for {job.placement_type}")
    specs = {s["specId"]: s for s in ref["videoSpecs" if job.video else "imageSpecs"]}
    info = video_info(job.file) if job.video else png_info(job.file)
    if info is None:
        print(f"  ffprobe not found, so {job.file.name} is not checked before upload")
        return "unchecked"
    problems = []
    for spec_id in mapping["specs"]:
        spec = specs.get(spec_id)
        if spec is None:
            continue
        dims = spec["dimensions"]
        why = []
        if not (dims["minWidth"] <= info["width"] <= dims["maxWidth"] and dims["minHeight"] <= info["height"] <= dims["maxHeight"]):
            why.append(f"{info['width']}x{info['height']}")
        if job.file.suffix.lower() not in spec["fileExtensions"]:
            why.append(job.file.suffix)
        if job.file.stat().st_size > spec["maxFileSize"]:
            why.append(f"{job.file.stat().st_size} bytes")
        if not job.video and info["alpha"] and not spec.get("alphaAllowed"):
            why.append("alpha channel")
        if job.video:
            if not any(r["minFps"] - 0.01 <= info["fps"] <= r["maxFps"] + 0.01 for r in spec.get("frameRates") or []):
                why.append(f"{info['fps']:.2f} fps")
            span = spec.get("duration")
            if span and not iso_seconds(span["min"]) <= info["duration"] <= iso_seconds(span["max"]):
                why.append(f"{info['duration']:.1f} s")
            if spec.get("audioRequired") and not info["audio"]:
                why.append("no audio track")
        if not why:
            return spec["shortName"]
        problems.append(f"{spec['shortName']}: {', '.join(why)}")
    raise ASCError(f"{job.file.name} matches no {job.label} spec\n  " + "\n  ".join(problems))


def wait_for_library(api: Client, path: str, name: str, timeout: float) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        attrs = api.get(path)["data"]["attributes"]
        if attrs.get("state") in PLACEABLE:
            return
        if attrs.get("state") == "FAILED":
            raise ASCError(f"Apple rejected {name}: {json.dumps(attrs.get('stateDetails'))}")
        time.sleep(5)
    print(f"  {name} is still processing; its placements show as processing until it finishes")


def library_asset(api: Client, library_id: str, job: MediaJob, poster: str | None) -> str:
    """The asset for the job's file: one already in the library with the same
    content, or a new upload. The reference name carries a hash of the file,
    so running this again uploads nothing."""
    kind = "Videos" if job.video else "Images"
    path = f"/v1/appAssetLibrary{kind}"
    digest = hashlib.sha256(job.file.read_bytes()).hexdigest()[:12]
    name = f"{job.file.stem} {digest}"
    found = [a for a in api.get_all(f"/v1/appAssetLibraries/{library_id}/{kind.lower()}")
             if a["attributes"].get("referenceName") == name and a["attributes"].get("state") in PLACEABLE | {"UPLOAD_COMPLETE"}]
    if found:
        asset = found[0]
        print(f"  {name} is already in the asset library")
        if poster and asset["attributes"].get("previewFrameTimeCode") != poster:
            api.write("PATCH", f"{path}/{asset['id']}",
                      {"data": {"type": f"appAssetLibrary{kind}", "id": asset["id"], "attributes": {"previewFrameTimeCode": poster}}},
                      f"set the poster frame of {name} to {poster}")
        if api.apply:
            wait_for_library(api, f"{path}/{asset['id']}", name, 900 if job.video else 120)
        return asset["id"]
    attrs: dict[str, Any] = {"fileName": job.file.name, "fileSize": job.file.stat().st_size,
                             "category": job.category, "referenceName": name}
    if poster:
        attrs["previewFrameTimeCode"] = poster
    body = {"data": {"type": f"appAssetLibrary{kind}", "attributes": attrs,
                     "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": library_id}}}}}
    asset_id = upload_asset(api, path, body, job.file, f"appAssetLibrary{kind}", checksum=False)
    if api.apply:
        wait_for_library(api, f"{path}/{asset_id}", name, 900 if job.video else 120)
    return asset_id


def place_asset(api: Client, loc: dict, job: MediaJob, asset_id: str) -> None:
    """Makes the asset the only one in the job's placement group on this
    localisation. Placements cannot be edited, so an older one is removed
    first; the asset it showed stays in the library."""
    locale = loc["attributes"]["locale"]
    relation = "video" if job.video else "image"
    current = api.get(f"/v1/appStoreVersionLocalizations/{loc['id']}/placements",
                      **{"filter[placementType]": job.placement_type, "filter[placementGroup]": job.group,
                         "include": "image,video", "limit": 50})
    names = {i["id"]: i["attributes"].get("referenceName") or i["attributes"].get("fileName") for i in current.get("included", [])}
    placed = [(p, (p["relationships"].get(relation) or {}).get("data") or {}) for p in current.get("data", [])]
    if any(linked.get("id") == asset_id for _, linked in placed) and len(placed) == 1:
        print(f"  {locale}: {job.label} is current")
        return
    for placement, linked in placed:
        shown = names.get(linked.get("id"), "an asset")
        api.write("DELETE", f"/v1/appAssetLibraryPlacements/{placement['id']}", None,
                  f"remove the {job.label} showing {shown} from {locale}")
    api.write("POST", "/v1/appAssetLibraryPlacements",
              {"data": {"type": "appAssetLibraryPlacements",
                        "attributes": {"placementType": job.placement_type, "placementGroup": job.group},
                        "relationships": {
                            relation: {"data": {"type": f"appAssetLibrary{'Videos' if job.video else 'Images'}", "id": asset_id}},
                            "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}},
              f"place {job.file.name} as the {job.label} on {locale}")


def cmd_media(api: Client, args) -> int:
    jobs = [j for j in media_jobs(args) if j.file.is_file()]
    for job in media_jobs(args):
        if not job.file.is_file():
            print(f"No {job.label} at {job.file}; skipping it")
    if not jobs:
        print("Nothing to place. Render the art with scripts/store_art.py and the preview with ios/AppStore/preview/render.ts.")
        return 1
    if not api.online:
        print("No credentials: App Store Connect can't be read, so nothing can be checked or planned.")
        return 2
    app = find_app(api)
    library_id = api.get(f"/v1/apps/{app['id']}/assetLibrary")["data"]["id"]
    ref_items = api.get("/v1/appAssetLibraryRefData")["data"]
    ref = (ref_items[0] if isinstance(ref_items, list) else ref_items)["attributes"]

    versions = api.get_all(f"/v1/apps/{app['id']}/appStoreVersions", **{"filter[platform]": "IOS"})
    editable = [v for v in versions if v["attributes"].get("appVersionState") in EDITABLE_APP_VERSION_STATES]
    if not editable:
        print("No version is being prepared. Create the next version in App Store Connect, then run this again.")
        return 1
    version = editable[0]
    locs = api.get_all(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    print(f"Version {version['attributes'].get('versionString')}: "
          f"{', '.join(l['attributes']['locale'] for l in locs)}\n")

    for job in jobs:
        print(f"{job.label.capitalize()}: {job.file.relative_to(ROOT) if job.file.is_relative_to(ROOT) else job.file}")
        print(f"  matches {check_media(ref, job)}")
        asset_id = library_asset(api, library_id, job, job.poster)
        for loc in locs:
            place_asset(api, loc, job, asset_id)
        print()
    print("The header and search results art appear on iOS 27 and later. Nothing here submits; "
          "they go to review with the version.")
    finish(api, "media")
    return 0


def finish(api: Client, what: str) -> None:
    if api.writes == 0:
        print(f"Nothing to change; App Store Connect matches the {what} folders.")
    elif api.apply:
        print(f"Done: {api.writes} writes. Nothing was submitted for review.")
    else:
        print(f"Dry run: {api.writes} writes would be sent. Run again with --apply (make appstore-{what} APPLY=1).")


# ---------------------------------------------------------------- CLI


def parse_date(value: str) -> dt.date:
    try:
        return dt.date.fromisoformat(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"expected YYYY-MM-DD, got {value!r}") from exc


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="asc.py", description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter,
                                     epilog="Credentials: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH. Nothing is ever submitted for review.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status", help="latest 5 builds with processing and TestFlight state")
    ev = sub.add_parser("events", help="create or update the in-app events (dry run unless --apply)")
    ev.add_argument("--start", type=parse_date, help="date the schedules are computed from (default today); "
                                                     "for crews-and-tournaments, the day 1.3.0 goes live")
    ev.add_argument("--images-only", action="store_true",
                    help="only replace each event's card and details images; create nothing and leave the text and schedule")
    ev.add_argument("--art", type=Path, help="folder with events/<slug>/event-card.png and event-details.png "
                    "(default: the screenshots branch)")
    ev.add_argument("--apply", action="store_true", help="send the writes")
    pg = sub.add_parser("pages", help="create or update the custom product pages (dry run unless --apply)")
    pg.add_argument("--images-only", action="store_true",
                    help="only replace each page's screenshots; create no page and leave promotional text and keywords")
    pg.add_argument("--art", type=Path, help="store art folder; screenshots come from its 6.9/ (default: framed "
                    "captures on the screenshots branch)")
    pg.add_argument("--apply", action="store_true", help="send the writes")
    gc = sub.add_parser("gamecenter", help="Game Center achievements, leaderboards and challenges (dry run unless --apply)")
    gc.add_argument("--apply", action="store_true", help="send the writes")
    md = sub.add_parser("media", help="app preview, header and search results art (dry run unless --apply)")
    md.add_argument("--preview", type=Path, default=MEDIA_DIR / "preview.mp4", help="886x1920 app preview")
    header = MEDIA_DIR / "creative" / "header.mp4"
    md.add_argument("--header", type=Path, default=header if header.is_file() else header.with_suffix(".png"),
                    help="3840x1646 header video (header.mp4, the default when it exists) or art (header.png)")
    md.add_argument("--header-poster", default="00:00:00:00", help="poster frame of a header video as HH:MM:SS:FF")
    md.add_argument("--search", type=Path, default=MEDIA_DIR / "creative" / "search.png", help="3:2 search results art")
    md.add_argument("--poster", help="poster frame as HH:MM:SS:FF (default: poster in ios/AppStore/preview.json)")
    md.add_argument("--apply", action="store_true", help="send the writes")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    creds = Credentials.from_env()
    apply = getattr(args, "apply", False)
    if apply and creds is None:
        print("error: --apply needs ASC_KEY_ID, ASC_ISSUER_ID and the key file", file=sys.stderr)
        return 2
    api = Client(creds, apply)
    try:
        return {"status": cmd_status, "events": cmd_events, "pages": cmd_pages,
                "gamecenter": cmd_gamecenter, "media": cmd_media}[args.command](api, args)
    except ASCError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
