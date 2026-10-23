"""Which fish are on record at each bundled South African water.

Pulls every georeferenced occurrence of the app's species in South Africa from
GBIF (museum specimens, surveys and research-grade iNaturalist observations;
no key needed), and attaches each record to the bundled water it falls on or
beside. Writes ios/Currents/Resources/Data/water_species_za.json:

    {"source": ..., "generated": "YYYY-MM-DD",
     "water": {"<osm id>": [[speciesId, records, latestYear], ...]}}

Run from the repo root (stdlib only). Responses are cached under
.cache/gbif, so a rerun only fetches what is missing:

    python3 scripts/build_water_species.py
"""
import json
import math
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "ios/Currents/Resources/Data"
CACHE = ROOT / ".cache/gbif"
API = "https://api.gbif.org/v1"
COUNTRY = "ZA"

# A record counts for a water when it lies within the water's own radius
# plus this margin (a shore, an inflow, a weir just below the wall).
MARGIN_KM = 0.6
# Records whose position is vaguer than this say nothing about one water.
MAX_UNCERTAINTY_M = 2000
SKIP_BASIS = {"FOSSIL_SPECIMEN", "LIVING_SPECIMEN"}
# GBIF answers 429 above a few parallel requests.
WORKERS = 3


def get(path: str, params: dict) -> dict:
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    key = CACHE / (urllib.parse.quote(f"{path}?{urllib.parse.urlencode(sorted(params.items()))}", safe="") + ".json")
    if key.exists():
        return json.loads(key.read_text())
    for attempt in range(8):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Currents data build"})
            with urllib.request.urlopen(req, timeout=60) as r:
                body = json.loads(r.read())
            key.write_text(json.dumps(body))
            return body
        except Exception as e:  # network blips and 429s: back off and retry
            if attempt == 7:
                raise RuntimeError(f"{url}: {e}") from e
            wait = 2 ** attempt * 2
            retry = getattr(e, "headers", None) and e.headers.get("Retry-After")
            if retry and retry.isdigit():
                wait = max(wait, int(retry))
            time.sleep(wait)
    raise AssertionError


def match(species: dict) -> tuple[int, int | None]:
    body = get("species/match", {"name": species["scientificName"], "strict": "true"})
    if body.get("matchType") in ("EXACT", "FUZZY") and body.get("rank") in ("SPECIES", "SUBSPECIES"):
        return species["id"], body.get("speciesKey") or body.get("usageKey")
    return species["id"], None


def occurrence_params(key: int) -> dict:
    return {"taxonKey": key, "country": COUNTRY, "hasCoordinate": "true", "hasGeospatialIssue": "false",
            "occurrenceStatus": "PRESENT"}


def records(key: int) -> list[dict]:
    out, offset = [], 0
    while True:
        body = get("occurrence/search", {**occurrence_params(key), "limit": 300, "offset": offset})
        for r in body.get("results", []):
            if r.get("basisOfRecord") in SKIP_BASIS:
                continue
            u = r.get("coordinateUncertaintyInMeters")
            if u is not None and u > MAX_UNCERTAINTY_M:
                continue
            out.append({"lat": r["decimalLatitude"], "lon": r["decimalLongitude"], "year": r.get("year")})
        offset += 300
        if body.get("endOfRecords", True) or offset >= 100_000:
            return out


def km(lat1, lon1, lat2, lon2) -> float:
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    return 6371 * math.hypot(dlat, dlon)


def main() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    species = json.loads((DATA / "species_seed.json").read_text())
    waters = json.loads((DATA / "explore_water_za.json").read_text())["water"]

    with ThreadPoolExecutor(WORKERS) as pool:
        keys = dict(pool.map(match, species))
    matched = {sid: k for sid, k in keys.items() if k}
    print(f"matched {len(matched)} of {len(species)} species to GBIF", file=sys.stderr)

    def count(item):
        sid, k = item
        return sid, k, get("occurrence/search", {**occurrence_params(k), "limit": 0})["count"]

    with ThreadPoolExecutor(WORKERS) as pool:
        present = [(sid, k) for sid, k, n in pool.map(count, matched.items()) if n > 0]
    print(f"{len(present)} species have records in {COUNTRY}", file=sys.stderr)

    # Grid the waters so each record only checks its neighbours.
    cell = 0.25
    grid: dict[tuple, list] = {}
    for w in waters:
        w["r"] = math.sqrt(w["km2"] / math.pi) + MARGIN_KM
        grid.setdefault((int(w["lat"] // cell), int(w["lon"] // cell)), []).append(w)

    found: dict[int, dict[int, list]] = {}

    def pull(item):
        sid, k = item
        return sid, records(k)

    with ThreadPoolExecutor(WORKERS) as pool:
        for sid, recs in pool.map(pull, present):
            for rec in recs:
                gy, gx = int(rec["lat"] // cell), int(rec["lon"] // cell)
                best = None
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        for w in grid.get((gy + dy, gx + dx), []):
                            d = km(rec["lat"], rec["lon"], w["lat"], w["lon"])
                            if d <= w["r"] and (best is None or d < best[0]):
                                best = (d, w)
                if best is None:
                    continue
                entry = found.setdefault(best[1]["osm"], {}).setdefault(sid, [0, None])
                entry[0] += 1
                if rec["year"] and (entry[1] is None or rec["year"] > entry[1]):
                    entry[1] = rec["year"]

    out = {
        "source": "GBIF.org occurrence records (CC0 and CC BY), matched to OpenStreetMap waters",
        "generated": date.today().isoformat(),
        "water": {str(osm): sorted(([sid, n, y] for sid, (n, y) in by.items()), key=lambda e: -e[1])
                  for osm, by in sorted(found.items())},
    }
    (DATA / "water_species_za.json").write_text(json.dumps(out, separators=(",", ":")) + "\n")
    pairs = sum(len(v) for v in out["water"].values())
    print(f"{len(out['water'])} of {len(waters)} waters have records, {pairs} water-species pairs", file=sys.stderr)


if __name__ == "__main__":
    main()
