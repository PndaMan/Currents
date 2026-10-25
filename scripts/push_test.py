# /// script
# requires-python = ">=3.11"
# dependencies = ["cryptography>=42", "requests>=2.32"]
# ///
"""Send every CloudKit push the app subscribes to, to one angler's iPhone.

The app gets its remote notifications from CKQuerySubscriptions on the public
database: CloudKit pushes when a record matching a subscription's predicate is
saved. This script saves such records as a fake angler (code PUSHTEST, name
"Push test"), one at a time with a pause between them, so a single device can
receive every notification without a second phone. It talks to CloudKit Web
Services with a server-to-server key, which only reaches the public database.

  uv run scripts/push_test.py --code ABC123            dry run: print the plan
  uv run scripts/push_test.py --code ABC123 --apply    create, wait 60 s, delete
  uv run scripts/push_test.py --code ABC123 --cleanup --apply
                                                       delete leftover PUSHTEST records
  make push-test CODE=ABC123 [APPLY=1]

Pushes sent, in order (pick some with --only, drop some with --skip):

  friend-request    FriendRequest to you                  "Push test wants to be friends"
  trip-invite       GroupInvite to you (for a new trip)   "Push test invited you to ..."
  request-accepted  FriendRequest from you, accepted      "Friend request accepted"
  crew-post         CrewPost in your first crew           "<crew>: Push test landed a ..."
                    (--crew CODE picks one, --all-crews does every crew)
  live-trip         GroupTrip started in that crew        "Push test started a live trip"
  reaction          CrewReaction on your newest crew post "Push test reacted ..."
  comment           CrewComment on that post              "Push test: ..."
  trip-catch        LeaderCatch on your newest live group trip
                    (start a trip on the phone first; skipped when none is live)

There is no Tournament subscription in the app: a tournament team starting
fires the live-trip push and team catches fire the trip-catch push.

Side effects worth knowing:
  - Crew posts and live trips notify every member of that crew, not only you.
    Use --crew with a crew where you are alone to keep it private.
  - request-accepted makes your app add PUSHTEST as a friend. Remove it in the
    app afterwards, or --skip request-accepted.
  - Records your own app writes in reply (accepting the request, joining the
    test trip) are yours and are left alone.

Every run is a dry run unless --apply is given. Without credentials the dry run
prints the plan with placeholders; with them it also reads your profile, crews,
posts and trips (reads only) and prints the exact records.

After creating, the script waits --wait seconds (default 60) and deletes every
record it made; --keep skips that. --cleanup finds records authored by PUSHTEST
(friend requests, invites, trips and their host memberships, catches, and posts,
reactions and comments in your crews) and deletes them with --apply.

Credentials come from the environment, or from .env.local through
scripts/with_ck_env.sh (the make target uses it):
  CK_KEY_ID     the server-to-server key ID from CloudKit Console
  CK_KEY_PATH   the PEM EC private key (prime256v1) for that key
  CK_ENV        production (default, what TestFlight uses) or development
  CK_CONTAINER  defaults to iCloud.com.aidanmcconnon.currents

Request signing: https://developer.apple.com/library/archive/documentation/
DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import secrets
import sys
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

API = "https://api.apple-cloudkit.com"
DEFAULT_CONTAINER = "iCloud.com.aidanmcconnon.currents"

TEST_CODE = "PUSHTEST"
TEST_NAME = "Push test"
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # same as the app's join codes
REACTION = "\U0001F525"

STEPS = ["friend-request", "trip-invite", "request-accepted", "crew-post",
         "live-trip", "reaction", "comment", "trip-catch"]


# MARK: - CloudKit Web Services


class CloudKitError(RuntimeError):
    pass


class CloudKit:
    """Signed requests to the public database with a server-to-server key."""

    def __init__(self, key_id: str, key_path: Path, environment: str, container: str):
        self.key_id = key_id
        pem = key_path.expanduser().read_bytes()
        key = serialization.load_pem_private_key(pem, password=None)
        if not isinstance(key, ec.EllipticCurvePrivateKey):
            raise CloudKitError(f"{key_path} is not an EC private key")
        self._key = key
        self.base = f"/database/1/{container}/{environment}/public"
        self.session = requests.Session()

    def post(self, operation: str, payload: dict[str, Any]) -> dict[str, Any]:
        subpath = f"{self.base}/{operation}"
        body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()
        date = dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        body_hash = base64.b64encode(hashlib.sha256(body).digest()).decode()
        message = f"{date}:{body_hash}:{subpath}".encode()
        signature = base64.b64encode(self._key.sign(message, ec.ECDSA(hashes.SHA256()))).decode()
        headers = {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": self.key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        }
        for attempt in range(3):
            try:
                r = self.session.post(API + subpath, data=body, headers=headers, timeout=30)
            except requests.RequestException as e:
                if attempt == 2:
                    raise CloudKitError(f"{operation}: {e}") from e
                time.sleep(2 * (attempt + 1))
                continue
            if r.status_code >= 500 and attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            if r.status_code != 200:
                raise CloudKitError(f"{operation}: HTTP {r.status_code} {r.text[:400]}")
            return r.json()
        raise CloudKitError(f"{operation}: no response")

    def query(self, record_type: str, field_name: str, value: str, limit: int = 200) -> list[dict]:
        payload = {
            "query": {
                "recordType": record_type,
                "filterBy": [{"comparator": "EQUALS", "fieldName": field_name,
                              "fieldValue": {"value": value, "type": "STRING"}}],
            },
            "resultsLimit": limit,
        }
        records: list[dict] = []
        while True:
            res = self.post("records/query", payload)
            records += [r for r in res.get("records", []) if "serverErrorCode" not in r]
            marker = res.get("continuationMarker")
            if not marker or len(records) >= limit:
                return records
            payload["continuationMarker"] = marker

    def lookup(self, names: list[str]) -> dict[str, dict]:
        """Found records by name; missing ones are left out."""
        found: dict[str, dict] = {}
        for i in range(0, len(names), 200):
            res = self.post("records/lookup", {"records": [{"recordName": n} for n in names[i:i + 200]]})
            for r in res.get("records", []):
                if "serverErrorCode" not in r:
                    found[r["recordName"]] = r
        return found

    def modify(self, operations: list[dict]) -> list[dict]:
        res = self.post("records/modify", {"operations": operations, "atomic": False})
        return res.get("records", [])


def val(record: dict, name: str, default: Any = None) -> Any:
    return record.get("fields", {}).get(name, {}).get("value", default)


def s(v: str) -> dict:
    return {"value": v, "type": "STRING"}


def d(v: float) -> dict:
    return {"value": float(v), "type": "DOUBLE"}


def i64(v: int) -> dict:
    return {"value": int(v), "type": "INT64"}


def ts(when: dt.datetime | None = None) -> dict:
    when = when or dt.datetime.now(dt.UTC)
    return {"value": int(when.timestamp() * 1000), "type": "TIMESTAMP"}


# MARK: - Plan


@dataclass
class Record:
    record_type: str
    name: str
    fields: dict[str, dict]
    # Pushes need a real creation (most subscriptions fire on create only), so
    # a leftover record with the same name fails loudly instead of updating.
    operation: str = "create"

    def op(self) -> dict:
        return {"operationType": self.operation,
                "record": {"recordType": self.record_type, "recordName": self.name, "fields": self.fields}}

    def describe(self) -> str:
        shown = ", ".join(f"{k}={v['value']!r}" for k, v in self.fields.items()
                          if v["type"] != "TIMESTAMP")
        return f"{self.record_type} {self.name}: {shown}"


@dataclass
class Step:
    key: str
    push: str
    records: list[Record] = field(default_factory=list)
    skipped: str | None = None


@dataclass
class Target:
    code: str
    name: str = "<your name>"
    region: str = "Global"
    crews: list[tuple[str, str]] = field(default_factory=list)  # (code, name)
    post: dict | None = None             # newest crew post authored by the target
    live_trip: tuple[str, str] | None = None  # (code, name) of a live group trip


def join_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(6))


def load_target(ck: CloudKit, code: str) -> Target:
    t = Target(code=code)
    profile = ck.lookup([f"profile-{code}"]).get(f"profile-{code}")
    if profile is None:
        raise CloudKitError(f"no AnglerProfile profile-{code}: check the friend code and CK_ENV")
    t.name = val(profile, "displayName", f"Angler {code}")
    t.region = val(profile, "region", "") or "Global"

    crew_codes = sorted({val(r, "crewCode") for r in ck.query("CrewMember", "memberCode", code)} - {None})
    crews = ck.lookup([f"crew-{c}" for c in crew_codes])
    t.crews = [(c, val(crews[f"crew-{c}"], "name", "Crew")) for c in crew_codes if f"crew-{c}" in crews]

    posts = []
    for crew_code, _ in t.crews:
        posts += [p for p in ck.query("CrewPost", "crewCode", crew_code, limit=300)
                  if val(p, "authorCode") == code]
    if posts:
        t.post = max(posts, key=lambda p: val(p, "caughtAt", 0))

    group_codes = sorted({val(r, "groupCode") for r in ck.query("GroupMember", "memberCode", code)} - {None})
    trips = ck.lookup([f"grouptrip-{g}" for g in group_codes])
    live = [r for r in trips.values()
            if val(r, "endedAt") is None and val(r, "hostCode") != TEST_CODE]
    if live:
        newest = max(live, key=lambda r: val(r, "createdAt", 0))
        t.live_trip = (val(newest, "code"), val(newest, "name", "Group trip"))
    return t


def placeholder_target(code: str) -> Target:
    return Target(code=code, crews=[("<crew>", "<your first crew>")],
                  post={"recordName": "<your newest crew post>",
                        "fields": {"crewCode": {"value": "<its crew>"}}},
                  live_trip=("<live trip>", "<your live group trip>"))


def trip_records(code: str, name: str, crew_code: str | None) -> list[Record]:
    """A group trip hosted by PUSHTEST plus the host membership the app also writes."""
    fields = {"code": s(code), "name": s(name), "hostCode": s(TEST_CODE),
              "hostName": s(TEST_NAME), "createdAt": ts()}
    if crew_code:
        fields["crewCode"] = s(crew_code)
    return [
        Record("GroupTrip", f"grouptrip-{code}", fields),
        Record("GroupMember", f"member-{code}-{TEST_CODE}",
               {"groupCode": s(code), "memberCode": s(TEST_CODE),
                "memberName": s(TEST_NAME), "joinedAt": ts()}),
    ]


def build_plan(t: Target, crews: list[tuple[str, str]], wanted: list[str]) -> tuple[list[Record], list[Step]]:
    me = t.code
    setup = [Record("AnglerProfile", f"profile-{TEST_CODE}", {
        "displayName": s(TEST_NAME), "friendCode": s(TEST_CODE), "bio": s("Test account for push alerts"),
        "homeWater": s(""), "region": s(t.region), "memberSince": ts(), "updatedAt": ts()},
        operation="forceReplace")]
    steps: list[Step] = []

    if "friend-request" in wanted:
        steps.append(Step("friend-request", f"New friend request: {TEST_NAME} wants to be friends", [
            Record("FriendRequest", f"friendreq-{TEST_CODE}-{me}", {
                "fromCode": s(TEST_CODE), "fromName": s(TEST_NAME), "toCode": s(me),
                "status": s("pending"), "createdAt": ts()})]))

    if "trip-invite" in wanted:
        code, name = join_code(), "Push test trip"
        # The invite must point at a live trip or the app discards it as stale.
        setup += trip_records(code, name, None)
        steps.append(Step("trip-invite", f"Trip invite: {TEST_NAME} invited you to “{name}”", [
            Record("GroupInvite", f"invite-{code}-{me}", {
                "groupCode": s(code), "tripName": s(name), "fromCode": s(TEST_CODE),
                "fromName": s(TEST_NAME), "toCode": s(me), "createdAt": ts()})]))

    if "request-accepted" in wanted:
        steps.append(Step("request-accepted", "Friend request accepted", [
            Record("FriendRequest", f"friendreq-{me}-{TEST_CODE}", {
                "fromCode": s(me), "fromName": s(t.name), "toCode": s(TEST_CODE),
                "status": s("accepted"), "createdAt": ts()})]))

    if "crew-post" in wanted:
        if not crews:
            steps.append(Step("crew-post", "crew post", skipped="you are not in any crew"))
        for crew_code, crew_name in crews:
            post_id = f"crewpost-{crew_code}-{uuid.uuid4().hex.upper()}"
            steps.append(Step("crew-post", f"{crew_name}: {TEST_NAME} landed a Largemouth bass", [
                Record("CrewPost", post_id, {
                    "crewCode": s(crew_code), "authorCode": s(TEST_CODE), "authorName": s(TEST_NAME),
                    "species": s("Largemouth bass"), "weightKg": d(1.8), "lengthCm": d(42),
                    "caughtAt": ts(), "caption": s("Test post for push alerts"), "hasPhoto": i64(0)})]))

    if "live-trip" in wanted:
        if not crews:
            steps.append(Step("live-trip", "live trip", skipped="you are not in any crew"))
        for crew_code, crew_name in crews:
            steps.append(Step("live-trip", f"{crew_name}: {TEST_NAME} started a live trip",
                              trip_records(join_code(), "Push test live trip", crew_code)))

    post = t.post
    for key in ("reaction", "comment"):
        if key not in wanted:
            continue
        if post is None:
            steps.append(Step(key, key, skipped="none of your crews has a post by you"))
            continue
        post_id, crew_code = post["recordName"], val(post, "crewCode")
        if key == "reaction":
            steps.append(Step(key, f"Your catch got a reaction: {TEST_NAME} reacted {REACTION}", [
                Record("CrewReaction", f"crewreact-{post_id}-{TEST_CODE}", {
                    "postId": s(post_id), "crewCode": s(crew_code), "postAuthorCode": s(me),
                    "reactorCode": s(TEST_CODE), "reactorName": s(TEST_NAME),
                    "emoji": s(REACTION), "createdAt": ts()})]))
        else:
            text = "Nice fish! (push test)"
            steps.append(Step(key, f"New comment on your catch: {TEST_NAME}: {text}", [
                Record("CrewComment", f"crewcomment-{str(uuid.uuid4()).upper()}", {
                    "postId": s(post_id), "crewCode": s(crew_code), "postAuthorCode": s(me),
                    "authorCode": s(TEST_CODE), "authorName": s(TEST_NAME),
                    "text": s(text), "createdAt": ts()})]))

    if "trip-catch" in wanted:
        if t.live_trip is None:
            steps.append(Step("trip-catch", "trip catch",
                              skipped="you are on no live group trip; start one on the phone and run again"))
        else:
            code, name = t.live_trip
            steps.append(Step("trip-catch", f"{name}: {TEST_NAME} just landed a Kob on the trip!", [
                Record("LeaderCatch", f"catch-{TEST_CODE}-{str(uuid.uuid4()).upper()}", {
                    "anglerName": s(TEST_NAME), "friendCode": s(TEST_CODE), "species": s("Kob"),
                    "weightKg": d(3.2), "lengthCm": d(68), "region": s(t.region),
                    "caughtAt": ts(), "groupCode": s(code), "hasPhoto": i64(0)})]))

    return setup, steps


# MARK: - Create and delete


def save(ck: CloudKit, records: list[Record]) -> list[Record]:
    saved: list[Record] = []
    results = ck.modify([r.op() for r in records])
    by_name = {r.get("recordName"): r for r in results}
    for rec in records:
        res = by_name.get(rec.name, {})
        if "serverErrorCode" in res or not res:
            print(f"    failed {rec.record_type} {rec.name}: "
                  f"{res.get('serverErrorCode', 'no result')} {res.get('reason', '')}".rstrip())
            if res.get("serverErrorCode") in ("CONFLICT", "RECORD_EXISTS"):
                print("    a record with that name is left over from an earlier run: --cleanup --apply")
        else:
            saved.append(rec)
    return saved


def delete(ck: CloudKit, names: list[str]) -> int:
    failed = 0
    for i in range(0, len(names), 200):
        ops = [{"operationType": "forceDelete", "record": {"recordName": n}} for n in names[i:i + 200]]
        for res in ck.modify(ops):
            code = res.get("serverErrorCode")
            if code and code != "NOT_FOUND":
                failed += 1
                print(f"    could not delete {res.get('recordName')}: {code} {res.get('reason', '')}")
    return failed


def find_leftovers(ck: CloudKit, code: str | None) -> list[tuple[str, str]]:
    """(recordType, recordName) of every record PUSHTEST authored that can be found."""
    found: dict[str, str] = {}

    def add(records: list[dict]) -> None:
        for r in records:
            found[r["recordName"]] = r.get("recordType", "?")

    add(ck.query("LeaderCatch", "friendCode", TEST_CODE))
    add(ck.query("FriendRequest", "fromCode", TEST_CODE))
    add(ck.query("FriendRequest", "toCode", TEST_CODE))
    members = ck.query("GroupMember", "memberCode", TEST_CODE)
    add(members)
    trips = ck.lookup([f"grouptrip-{val(m, 'groupCode')}" for m in members if val(m, "groupCode")])
    add([r for r in trips.values() if val(r, "hostCode") == TEST_CODE])
    add(list(ck.lookup([f"profile-{TEST_CODE}"]).values()))
    if code:
        add([r for r in ck.query("GroupInvite", "toCode", code) if val(r, "fromCode") == TEST_CODE])
        crew_codes = {val(r, "crewCode") for r in ck.query("CrewMember", "memberCode", code)} - {None}
        for crew in sorted(crew_codes):
            add([r for r in ck.query("CrewPost", "crewCode", crew, 300) if val(r, "authorCode") == TEST_CODE])
            add([r for r in ck.query("CrewReaction", "crewCode", crew, 800) if val(r, "reactorCode") == TEST_CODE])
            add([r for r in ck.query("CrewComment", "crewCode", crew, 800) if val(r, "authorCode") == TEST_CODE])
            add([r for r in ck.query("GroupTrip", "crewCode", crew, 100) if val(r, "hostCode") == TEST_CODE])
    return sorted((t, n) for n, t in found.items())


# MARK: - Main


def connect() -> CloudKit | None:
    key_id, key_path = os.environ.get("CK_KEY_ID"), os.environ.get("CK_KEY_PATH")
    if not key_id or not key_path:
        return None
    env = os.environ.get("CK_ENV", "production")
    if env not in ("production", "development"):
        sys.exit(f"CK_ENV must be production or development, not {env!r}")
    path = Path(key_path).expanduser()
    if not path.is_file():
        sys.exit(f"CK_KEY_PATH does not point at a file: {path}")
    return CloudKit(key_id, path, env, os.environ.get("CK_CONTAINER", DEFAULT_CONTAINER))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="\n".join(__doc__.splitlines()[2:]))
    ap.add_argument("--code", help="your friend code (Profile in the app)")
    ap.add_argument("--apply", action="store_true", help="really create (or with --cleanup, delete) records")
    ap.add_argument("--cleanup", action="store_true", help="find leftover PUSHTEST records and delete them")
    ap.add_argument("--crew", help="crew code for crew-post and live-trip (default: your first crew)")
    ap.add_argument("--all-crews", action="store_true", help="crew-post and live-trip in every crew")
    ap.add_argument("--only", help=f"comma-separated subset of: {','.join(STEPS)}")
    ap.add_argument("--skip", help="comma-separated steps to leave out")
    ap.add_argument("--interval", type=float, default=5.0, help="seconds between pushes (default 5)")
    ap.add_argument("--wait", type=float, default=60.0, help="seconds before deleting (default 60)")
    ap.add_argument("--keep", action="store_true", help="do not delete the records afterwards")
    args = ap.parse_args()

    code = args.code.strip().upper() if args.code else None
    if not code and not args.cleanup:
        ap.error("--code is required")

    def parse(value: str | None) -> list[str]:
        items = [x.strip() for x in (value or "").split(",") if x.strip()]
        unknown = set(items) - set(STEPS)
        if unknown:
            ap.error(f"unknown step(s): {', '.join(sorted(unknown))}")
        return items

    wanted = parse(args.only) or list(STEPS)
    wanted = [k for k in wanted if k not in parse(args.skip)]

    try:
        ck = connect()
    except (CloudKitError, ValueError) as e:
        sys.exit(f"could not load the key: {e}")
    if ck is None:
        if args.apply:
            sys.exit("CK_KEY_ID and CK_KEY_PATH are not set (add them to .env.local); nothing was sent")
        print("CK_KEY_ID / CK_KEY_PATH not set: showing the plan with placeholders, nothing is read or sent.\n")
    else:
        print(f"CloudKit {ck.base}\n")

    try:
        if args.cleanup:
            if ck is None:
                print("Cleanup needs credentials to find records.")
                return 0
            leftovers = find_leftovers(ck, code)
            if not leftovers:
                print("No PUSHTEST records found.")
                return 0
            for rtype, name in leftovers:
                print(f"  {rtype} {name}")
            if not args.apply:
                print(f"\nDry run: {len(leftovers)} record(s) would be deleted. Add --apply to delete.")
                return 0
            failed = delete(ck, [n for _, n in leftovers])
            print(f"\nDeleted {len(leftovers) - failed} of {len(leftovers)}.")
            return 1 if failed else 0

        target = load_target(ck, code) if ck else placeholder_target(code)
        crews = target.crews
        if args.crew:
            crews = [c for c in crews if c[0] == args.crew.upper()] or (
                [] if ck else [(args.crew.upper(), "<that crew>")])
            if not crews:
                sys.exit(f"you are not a member of crew {args.crew.upper()}")
        elif not args.all_crews:
            crews = crews[:1]

        print(f"Target {target.code} ({target.name}), {len(target.crews)} crew(s): "
              + (", ".join(f"{n} [{c}]" for c, n in target.crews) or "none"))
        setup, steps = build_plan(target, crews, wanted)
        print("\nSetup (no push):")
        for rec in setup:
            print(f"  {rec.describe()}")
        print("\nPushes:")
        for n, step in enumerate(steps, 1):
            if step.skipped:
                print(f"  {n}. {step.key}: skipped, {step.skipped}")
                continue
            print(f"  {n}. {step.key}: “{step.push}”")
            for rec in step.records:
                print(f"       {rec.describe()}")

        if not args.apply:
            print("\nDry run: nothing was created. Add --apply to send the pushes.")
            return 0

        created: list[Record] = save(ck, setup)
        if len(created) < len(setup):
            print("Setup records failed; stopping before any push.")
            delete(ck, [r.name for r in reversed(created)])
            return 1
        sent = [s for s in steps if not s.skipped]
        for n, step in enumerate(sent, 1):
            saved = save(ck, step.records)
            created += saved
            ok = len(saved) == len(step.records)
            print(f"  {'sent' if ok else 'FAILED'} {step.key}: “{step.push}”")
            if n < len(sent):
                time.sleep(args.interval)

        if args.keep:
            print(f"\nKept {len(created)} record(s). Remove them later with --cleanup --apply.")
            return 0
        print(f"\nWaiting {args.wait:.0f} s before deleting {len(created)} record(s) (Ctrl-C keeps them)...")
        try:
            time.sleep(args.wait)
        except KeyboardInterrupt:
            print("\nKept. Remove them later with --cleanup --apply.")
            return 130
        failed = delete(ck, [r.name for r in reversed(created)])
        print(f"Deleted {len(created) - failed} of {len(created)}.")
        return 1 if failed else 0
    except CloudKitError as e:
        print(f"CloudKit error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
