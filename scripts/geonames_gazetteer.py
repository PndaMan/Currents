# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Build the bundled gazetteer that names ramps away from bundled water.

An unnamed ramp or fishing access point on bundled water is called after
that water ("Ramp at Theewaterskloof Dam"). One on the coast or a river has
no water to take a name from, so the app names it after the nearest
populated place within 10 km instead ("Ramp near Hout Bay"). This script
writes those places to ios/Currents/Resources/Data/gazetteer_za.json:

    {"source": "...", "places": [[name, lat, lon], [name, lat, lon, 1], ...]}

Places are GeoNames feature class P (cities, towns, villages, and sections
such as Hout Bay or Muizenberg), with coordinates to 4 decimals (about
10 m). A fourth value of 1 marks a town, which the app prefers within 5 km
over a nearer section, farm or hamlet; a row without it is not a town. A
place is a town when it is

    a capital or administrative seat (PPLC, PPLA, PPLA2 to PPLA5), or
    a PPL with a population of 1000 or more, or
    a PPL with two or more alternate names, which GeoNames records for
    places people write about (Hout Bay, Kommetjie, Gordon's Bay) and not
    for the farm and hamlet points that sit beside them (An-de-Waterkant,
    Weltevreder)

Population is 0 for most places in the dump, so it cannot do the job alone.
Sections (PPLX), localities (PPLL) and farms (PPLF) are never towns.

Left out:

    historical, abandoned and destroyed places (PPLH, PPLQ, PPLW, PPLCH)
    old "... Location" ward names, which are not names anglers use
    a second place of the same name within 2 km (the bigger one is kept)
    a spelling variant within 5 km of a bigger place: names that differ only
    by apostrophes, case or a trailing " Central" ("Gordons Bay Central")

The " (2)" GeoNames adds to tell farms apart is dropped from names.

The file is kept under about 300 KB. When every place does not fit, only
places within 25 km of the coast or of a bundled water or ramp
(explore_water_za.json, explore_places_za.json) are kept; the coast is
taken from the GeoNames bays, coves, harbours, beaches and capes. The app
only names ramps within 10 km of a place, so the cut loses nothing it uses.

GeoNames data is CC BY 4.0 (credit "GeoNames", geonames.org). Download the
South Africa dump into an empty folder outside the repo:

    mkdir -p /tmp/geonames && cd /tmp/geonames
    curl -fLO https://download.geonames.org/export/dump/ZA.zip

Then, from the repo root:

    uv run scripts/geonames_gazetteer.py --geonames /tmp/geonames/ZA.zip --dry-run
    uv run scripts/geonames_gazetteer.py --geonames /tmp/geonames/ZA.zip
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import zipfile
from collections import defaultdict
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DATA = REPO / "ios/Currents/Resources/Data"
OUT_JSON = DATA / "gazetteer_za.json"
WATER_JSON = DATA / "explore_water_za.json"
PLACES_JSON = DATA / "explore_places_za.json"

MAX_BYTES = 300_000
MARGIN_M = 25_000
SAME_NAME_M = 2_000
VARIANT_NAME_M = 5_000
TOWN_POPULATION = 1_000
TOWN_ALTERNATES = 2

LEFT_OUT_CODES = {"PPLH", "PPLQ", "PPLW", "PPLCH"}
TOWN_CODES = {"PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLA5"}
# GeoNames bays, coves, harbours, beaches and capes, standing in for the coast.
COAST_CODES = {("H", "BAY"), ("H", "COVE"), ("H", "HBR"), ("T", "BCH"), ("T", "CAPE")}
# Bigger places first when two share a name nearby.
CODE_RANK = {"PPLC": 0, "PPLA": 1, "PPLA2": 2, "PPLA3": 3, "PPLA4": 4, "PPL": 5, "PPLX": 6, "PPLL": 7, "PPLF": 8}

# geoname table columns (readme.txt in the dump)
NAME, ALTERNATES, LAT, LON, CLASS, CODE, POPULATION = 1, 3, 4, 5, 6, 7, 14


def metres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Flat-earth distance, as BundledMapData.metres measures it."""
    x = (lon2 - lon1) * math.pi / 180 * math.cos((lat1 + lat2) / 2 * math.pi / 180)
    y = (lat2 - lat1) * math.pi / 180
    return math.hypot(x, y) * 6_371_000


class Grid:
    """Points by half-degree cell, so each point is only measured against its
    neighbours. A cell is at least 45 km across here, more than any distance
    asked of it."""

    def __init__(self, points: list[tuple[float, float]]) -> None:
        self.cells: dict[tuple[int, int], list[tuple[float, float]]] = defaultdict(list)
        for lat, lon in points:
            self.cells[self.key(lat, lon)].append((lat, lon))

    @staticmethod
    def key(lat: float, lon: float) -> tuple[int, int]:
        return math.floor(lat / 0.5), math.floor(lon / 0.5)

    def near(self, lat: float, lon: float, limit: float) -> bool:
        i, j = self.key(lat, lon)
        return any(
            metres(lat, lon, plat, plon) <= limit
            for di in (-1, 0, 1)
            for dj in (-1, 0, 1)
            for plat, plon in self.cells.get((i + di, j + dj), [])
        )


def read_rows(path: Path) -> tuple[list[list[str]], str]:
    """The geoname rows from ZA.zip (or an unzipped ZA.txt), and the dump date."""
    if path.suffix == ".zip":
        with zipfile.ZipFile(path) as z:
            info = z.getinfo("ZA.txt")
            text = z.read(info).decode("utf-8")
            stamp = date(*info.date_time[:3]).isoformat()
    else:
        text = path.read_text(encoding="utf-8")
        stamp = date.fromtimestamp(path.stat().st_mtime).isoformat()
    return [line.split("\t") for line in text.splitlines() if line], stamp


def clean(name: str) -> str:
    return re.sub(r"\s*\(\d+\)$", "", " ".join(name.split()))


def is_town(code: str, population: int, alternates: int) -> bool:
    """Whether a place is a town an angler would name a ramp after. Population
    is 0 for most places in the dump, so a PPL also counts when GeoNames holds
    several names for it."""
    if code in TOWN_CODES:
        return True
    return code == "PPL" and (population >= TOWN_POPULATION or alternates >= TOWN_ALTERNATES)


def fold_key(name: str) -> str:
    """The name without apostrophes, case or a trailing " Central", so that
    "Gordon’s Bay", "Gordons Bay" and "Gordons Bay Central" are one key."""
    key = " ".join(re.sub(r"['‘’ʼ`]", "", name).casefold().split())
    return re.sub(r" central$", "", key)


def populated(rows: list[list[str]]) -> list[dict]:
    places = []
    for r in rows:
        if r[CLASS] != "P" or r[CODE] in LEFT_OUT_CODES:
            continue
        name = clean(r[NAME])
        if not name or name.endswith(" Location"):
            continue
        population = int(r[POPULATION] or 0)
        town = is_town(r[CODE], population, len([a for a in r[ALTERNATES].split(",") if a.strip()]))
        places.append({
            "name": name,
            "lat": round(float(r[LAT]), 4),
            "lon": round(float(r[LON]), 4),
            "tier": 1 if town else 0,
            # Towns first, then the bigger feature codes and populations.
            "rank": (0 if town else 1, CODE_RANK.get(r[CODE], 9), -population),
        })
    return places


def drop_repeats(places: list[dict]) -> list[dict]:
    """One place per name within 2 km, the biggest, and one per spelling
    variant (see fold_key) within 5 km."""
    kept: dict[str, list[dict]] = defaultdict(list)
    for p in sorted(places, key=lambda p: (p["rank"], p["name"], p["lat"], p["lon"])):
        group = kept[fold_key(p["name"])]
        if any(metres(p["lat"], p["lon"], q["lat"], q["lon"])
               < (SAME_NAME_M if p["name"] == q["name"] else VARIANT_NAME_M) for q in group):
            continue
        group.append(p)
    return [p for group in kept.values() for p in group]


def encode(source: str, places: list[dict]) -> str:
    """Towns carry a fourth value of 1; the rest have three, which the app reads as tier 0."""
    rows = [[p["name"], p["lat"], p["lon"], *([1] if p["tier"] else [])]
            for p in sorted(places, key=lambda p: (p["name"], p["lat"], p["lon"]))]
    return json.dumps({"source": source, "places": rows}, ensure_ascii=False, separators=(",", ":")) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--geonames", type=Path, required=True, help="ZA.zip (or ZA.txt) from download.geonames.org")
    ap.add_argument("--out", type=Path, default=OUT_JSON)
    ap.add_argument("--dry-run", action="store_true", help="print the counts, write nothing")
    args = ap.parse_args()

    rows, stamp = read_rows(args.geonames)
    source = f"GeoNames (geonames.org), CC BY 4.0, ZA dump of {stamp}"
    places = drop_repeats(populated(rows))
    print(f"{sum(1 for r in rows if r[CLASS] == 'P')} populated places in the dump; {len(places)} after cleaning.")

    text = encode(source, places)
    if len(text.encode("utf-8")) > MAX_BYTES:
        water = json.loads(WATER_JSON.read_text(encoding="utf-8"))["water"]
        ramps = json.loads(PLACES_JSON.read_text(encoding="utf-8"))["places"]
        anchors = Grid([(w["lat"], w["lon"]) for w in water] + [(p["lat"], p["lon"]) for p in ramps])
        coast = Grid([(float(r[LAT]), float(r[LON])) for r in rows if (r[CLASS], r[CODE]) in COAST_CODES])
        before = len(places)
        places = [p for p in places
                  if anchors.near(p["lat"], p["lon"], MARGIN_M) or coast.near(p["lat"], p["lon"], MARGIN_M)]
        print(f"Over {MAX_BYTES // 1000} KB: kept the {len(places)} of {before} within "
              f"{MARGIN_M // 1000} km of the coast, a bundled water or a ramp.")
        text = encode(source, places)

    size = len(text.encode("utf-8"))
    print(f"{len(places)} places, {sum(p['tier'] for p in places)} of them towns, {size / 1000:.0f} KB.")
    if size > MAX_BYTES * 1.05:
        sys.exit("Still too big; nothing written.")
    if args.dry_run:
        print("Dry run; nothing written.")
        return
    args.out.write_text(text, encoding="utf-8")
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
