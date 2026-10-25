"""Adds the half-degree tiles off the South African coast to the coverage list.

The extract holds every South African feature, so a tile that is open sea
(south of the Namibian and Mozambican borders, outside the land polygon) has
nothing more for Overpass to add.
"""
import json, math, sys

def bounds(t):
    a, b = map(int, t.split("_"))
    return a * 0.5, a * 0.5 + 0.5, b * 0.5, b * 0.5 + 0.5

def is_sea(lat0, lat1, lon0, lon1):
    if lat1 <= -34.5:                      # south coast and beyond
        return True
    if lat1 <= -28.5 and lon1 <= 20.0:     # west coast, south of the Orange
        return True
    if lat1 <= -28.5 and lon0 >= 31.0:     # east coast, Durban down
        return True
    if lat1 <= -26.5 and lon0 >= 32.5:     # east coast, north to Kosi Bay
        return True
    return False

paths = sys.argv[1:]
data = [json.load(open(p)) for p in paths]
tiles = set(data[0]["tiles"])
added = []
for a in range(math.floor(-37 / 0.5), math.floor(-26 / 0.5) + 1):
    for b in range(math.floor(15 / 0.5), math.floor(34 / 0.5) + 1):
        t = f"{a}_{b}"
        if t in tiles:
            continue
        lat0, lat1, lon0, lon1 = bounds(t)
        if not is_sea(lat0, lat1, lon0, lon1):
            continue
        # only tiles touching the coverage ring, grown outward
        added.append(t)
# keep sea tiles within 2 tiles of covered land
ring = set()
for t in added:
    a, b = map(int, t.split("_"))
    if any(f"{a+da}_{b+db}" in tiles for da in range(-2, 3) for db in range(-2, 3)):
        ring.add(t)
print("sea tiles added", len(ring))
for d, p in zip(data, paths):
    d["tiles"] = sorted(set(d["tiles"]) | ring, key=lambda s: tuple(map(int, s.split("_"))))
    with open(p, "w") as f:
        json.dump(d, f, ensure_ascii=False, separators=(",", ":"))
