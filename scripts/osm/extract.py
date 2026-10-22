"""Extract named fishable water bodies and fishing access / slipways from an
OSM extract into compact JSON for the app bundle.

usage: extract.py <in.osm.pbf> <in.poly> <out_water.json> <out_access.json>

Input: the Geofabrik South Africa (with Lesotho) extract and its .poly from
download.geofabrik.de/africa/. Then run ocean_tiles.py on both outputs and
copy them to ios/Currents/Resources/Data/explore_water_za.json and
explore_places_za.json. Bump BundledMapData.waterVersion when the water changes.
"""
import json
import math
import re
import sys

import osmium

pbf, poly_path, out_water, out_access = sys.argv[1:5]

SKIP_WATER = {"wastewater", "sewage", "basin", "reflecting_pool", "swimming_pool",
              "fountain", "fish_pass", "lock", "salt_pool", "evaporator", "moat",
              "tank", "treatment", "settling", "pool", "salt_pan", "drain", "ditch",
              "harbour", "dock"}
RIVER_WATER = {"river", "canal", "stream", "rapids", "riverbank"}
MIN_KM2 = 0.01  # 1 ha; smaller named ponds are mostly garden and estate ponds
DAM_RE = re.compile(r"\b(dam|reservoir|damme)\b", re.I)
EST_RE = re.compile(r"\b(lagoon|estuary|bay|lagune|meer)\b", re.I)


def ring_area_km2(coords, lat0):
    """Shoelace on a local equirectangular projection, km^2."""
    kx = 111.320 * math.cos(math.radians(lat0))
    ky = 110.574
    s = 0.0
    n = len(coords)
    for i in range(n):
        x1, y1 = coords[i]
        x2, y2 = coords[(i + 1) % n]
        s += (x1 * kx) * (y2 * ky) - (x2 * kx) * (y1 * ky)
    return abs(s) / 2.0


def centroid(coords):
    sx = sum(c[0] for c in coords) / len(coords)
    sy = sum(c[1] for c in coords) / len(coords)
    return sx, sy


def point_on_surface(outer, inners):
    """Midpoint of the widest inside interval on a scanline through the
    ring's centroid latitude, like GEOS PointOnSurface."""
    _, cy = centroid(outer)
    xs = []
    for ring in [outer] + inners:
        n = len(ring)
        for i in range(n):
            x1, y1 = ring[i]
            x2, y2 = ring[(i + 1) % n]
            if (y1 > cy) != (y2 > cy):
                xs.append(x1 + (cy - y1) * (x2 - x1) / (y2 - y1))
    xs.sort()
    best = None
    for i in range(0, len(xs) - 1, 2):
        w = xs[i + 1] - xs[i]
        if best is None or w > best[0]:
            best = (w, (xs[i] + xs[i + 1]) / 2)
    if best is None:
        return centroid(outer)
    return best[1], cy


def classify(tags, name):
    water = tags.get("water", "")
    if DAM_RE.search(name):
        return "dam"
    if water == "lagoon" or tags.get("tidal") == "yes" or EST_RE.search(name):
        return "estuary"
    if water in ("marina",):
        return "coast"
    if water in RIVER_WATER or tags.get("waterway") in ("riverbank", "canal"):
        return "river"
    if water == "reservoir" or tags.get("landuse") == "reservoir":
        return "dam"
    return "lake"


def is_water(tags):
    if tags.get("natural") == "water":
        return True
    if tags.get("landuse") == "reservoir":
        return True
    if tags.get("waterway") == "riverbank":
        return True
    return False


def load_poly(path):
    polys, cur, holes = [], None, False
    with open(path) as f:
        lines = [l.strip() for l in f]
    i = 1
    while i < len(lines):
        l = lines[i]
        if l == "END":
            if cur is not None:
                polys.append((holes, cur))
                cur = None
            i += 1
            continue
        if cur is None:
            holes = l.startswith("!")
            cur = []
        else:
            x, y = map(float, l.split())
            cur.append((x, y))
        i += 1
    return polys


def inside(pt, ring):
    x, y = pt
    c = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            c = not c
    return c


def covered(pt, polys):
    ins = any(inside(pt, r) for h, r in polys if not h)
    out = any(inside(pt, r) for h, r in polys if h)
    return ins and not out


water = []
access = []

fp = (osmium.FileProcessor(pbf)
      .with_locations()
      .with_areas(osmium.filter.KeyFilter("natural", "landuse", "waterway", "water")))

for obj in fp:
    if obj.is_area():
        tags = obj.tags
        if not is_water(tags):
            continue
        name = tags.get("name") or tags.get("name:en")
        if not name:
            continue
        if tags.get("water", "") in SKIP_WATER or tags.get("intermittent") == "yes":
            continue
        if tags.get("leisure") in ("swimming_pool",) or tags.get("amenity") == "fountain":
            continue
        rings = []
        try:
            for outer in obj.outer_rings():
                o = [(n.lon, n.lat) for n in outer]
                inn = [[(n.lon, n.lat) for n in ir] for ir in obj.inner_rings(outer)]
                rings.append((o, inn))
        except osmium.InvalidLocationError:
            continue
        if not rings:
            continue
        lat0 = rings[0][0][0][1]
        area = 0.0
        for o, inn in rings:
            area += ring_area_km2(o, lat0) - sum(ring_area_km2(r, lat0) for r in inn)
        if area < MIN_KM2:
            continue
        big = max(rings, key=lambda r: ring_area_km2(r[0], lat0))
        lon, lat = point_on_surface(big[0], big[1])
        access_tag = tags.get("access", "")
        ele = tags.get("ele")
        try:
            ele = round(float(ele), 0) if ele else None
        except ValueError:
            ele = None
        water.append({
            "osm": obj.orig_id(),
            "name": name.strip(),
            "type": classify(tags, name),
            "lat": round(lat, 5),
            "lon": round(lon, 5),
            "km2": round(area, 3),
            "public": access_tag not in ("private", "no"),
            "ele": ele,
        })
    elif obj.is_node() or obj.is_way():
        leisure = obj.tags.get("leisure")
        if leisure not in ("fishing", "slipway"):
            continue
        if obj.tags.get("access") in ("private", "no"):
            continue
        if obj.is_node():
            if not obj.location.valid():
                continue
            lat, lon = obj.location.lat, obj.location.lon
            ref = f"node/{obj.id}"
        else:
            pts = [(n.lon, n.lat) for n in obj.nodes if n.location.valid()]
            if not pts:
                continue
            lon, lat = centroid(pts)
            ref = f"way/{obj.id}"
        kind = "access" if leisure == "fishing" else "ramp"
        name = obj.tags.get("name") or ("Fishing access" if kind == "access" else "Boat ramp")
        access.append({"id": ref, "name": name.strip(), "kind": kind,
                       "lat": round(lat, 5), "lon": round(lon, 5)})

# Merge same-name pieces of one water body (split riverbanks, multi-part
# dams): biggest piece leads, pieces within reach join it.
water.sort(key=lambda w: -w["km2"])
merged = []
for w in water:
    reach = 15.0 if w["type"] == "river" else 3.0
    k = math.cos(math.radians(w["lat"]))
    joined = False
    for m in merged:
        if m["name"].lower() != w["name"].lower() or m["type"] != w["type"]:
            continue
        d = math.hypot((m["lat"] - w["lat"]) * 111.0, (m["lon"] - w["lon"]) * 111.0 * k)
        if d < reach:
            m["km2"] = round(m["km2"] + w["km2"], 3)
            joined = True
            break
    if not joined:
        merged.append(dict(w))

polys = load_poly(poly_path)
tiles = []
for li in range(-70, -43):          # 0.5 degree rows, -35 .. -21.5
    for lo in range(32, 68):        # 16 .. 34 east
        pts = [((lo + dx) * 0.5, (li + dy) * 0.5) for dx, dy in
               ((0.5, 0.5), (0.05, 0.05), (0.95, 0.05), (0.05, 0.95), (0.95, 0.95))]
        if any(covered(c, polys) for c in pts):
            tiles.append(f"{li}_{lo}")

for m in merged:
    if m["public"]:
        del m["public"]
    if m["ele"] is None:
        del m["ele"]

with open(out_water, "w") as f:
    json.dump({"source": "OpenStreetMap contributors, ODbL", "tiles": tiles, "water": merged},
              f, separators=(",", ":"), ensure_ascii=False)
with open(out_access, "w") as f:
    json.dump({"source": "OpenStreetMap contributors, ODbL", "tiles": tiles, "places": access},
              f, separators=(",", ":"), ensure_ascii=False)

types = {}
for m in merged:
    types[m["type"]] = types.get(m["type"], 0) + 1
print(f"water raw={len(water)} merged={len(merged)} types={types} tiles={len(tiles)}")
print(f"access={len(access)} ramps={sum(1 for a in access if a['kind']=='ramp')}")
