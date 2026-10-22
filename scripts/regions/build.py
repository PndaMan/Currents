"""Build the predefined offline map areas: every country and its first-level
regions (provinces, states), from Natural Earth (public domain).

usage: python3 scripts/regions/build.py [--cache DIR]

Downloads the Natural Earth 1:10m admin 0 and admin 1 GeoJSON (pinned to a
release tag) into the cache folder, then writes:

  ios/Currents/Resources/Data/offline_regions.json
      countries and regions with a bounding box and area, for browsing,
      search and size estimates (the app names countries from their ISO
      code in the phone's language, this name is the fallback)
  ios/Currents/Resources/Data/offline_regions_shapes.json
      simplified outlines as encoded polylines (precision 1e4), so the app
      can draw an area and skip overview tiles outside it

Outlying islands far from the main land are left out of a region's box and
outline (Marion Island would otherwise stretch the Western Cape to 47 S).
Parts split at the antimeridian are moved next to the main part, so a box
may run past 180 or -180.
"""
import argparse
import json
import math
import os
import sys
import urllib.request

TAG = "v5.1.2"
BASE = f"https://raw.githubusercontent.com/nvkelso/natural-earth-vector/{TAG}/geojson/"
FILES = {
    "admin0": "ne_10m_admin_0_countries.geojson",
    "admin1": "ne_10m_admin_1_states_provinces.geojson",
}
SOURCE = f"Natural Earth 1:10m admin 0 and admin 1 ({TAG}), public domain"

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "ios", "Currents", "Resources", "Data")

EARTH_R_KM = 6371.0088
SIMPLIFY_DEG = 0.02          # about 2 km, plenty for drawing and tile masks
KEEP_SHARE = 0.02            # parts this share of the area are always kept
KEEP_NEAR_KM = 250.0         # smaller parts are kept when this close to the main part


def fetch(cache, key):
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, f"{TAG}-{FILES[key]}")
    if not os.path.exists(path):
        print(f"downloading {FILES[key]}", file=sys.stderr)
        urllib.request.urlretrieve(BASE + FILES[key], path)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def outer_rings(geometry):
    if geometry is None:
        return []
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"][0]]
    if geometry["type"] == "MultiPolygon":
        return [poly[0] for poly in geometry["coordinates"]]
    return []


def ring_area_km2(ring):
    """Area on the sphere (the same formula d3 and turf use)."""
    total = 0.0
    n = len(ring)
    for i in range(n):
        lon1, lat1 = ring[i]
        lon2, lat2 = ring[(i + 1) % n]
        total += math.radians(lon2 - lon1) * (2 + math.sin(math.radians(lat1)) + math.sin(math.radians(lat2)))
    return abs(total * EARTH_R_KM * EARTH_R_KM / 2.0)


def bbox(ring):
    lons = [p[0] for p in ring]
    lats = [p[1] for p in ring]
    return [min(lons), min(lats), max(lons), max(lats)]


def union(a, b):
    return [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]


def box_gap_km(a, b):
    """Rough distance between two boxes, 0 when they touch."""
    dlon = max(0.0, max(a[0], b[0]) - min(a[2], b[2]))
    dlat = max(0.0, max(a[1], b[1]) - min(a[3], b[3]))
    mid = math.radians((a[1] + a[3] + b[1] + b[3]) / 4)
    return math.hypot(dlon * 111.32 * math.cos(mid), dlat * 110.57)


def beside(ring, anchor_lon):
    """Moves a ring by 360 degrees when that puts it nearer the main part, so
    parts split at the antimeridian join up (Chukotka, Fiji, the Aleutians)."""
    b = bbox(ring)
    centre = (b[0] + b[2]) / 2
    if centre - anchor_lon > 180:
        return [[x - 360.0, y] for x, y in ring]
    if anchor_lon - centre > 180:
        return [[x + 360.0, y] for x, y in ring]
    return ring


def main_parts(rings):
    """The parts worth a download: big ones, and small ones near the main land."""
    rings = [r for r in rings if len(r) >= 4]
    if not rings:
        return [], 0.0
    parts = sorted(((ring_area_km2(r), r) for r in rings), key=lambda t: -t[0])
    total = sum(a for a, _ in parts)
    main_box = bbox(parts[0][1])
    anchor = (main_box[0] + main_box[2]) / 2
    kept = []
    for area, ring in parts:
        ring = beside(ring, anchor)
        if area >= total * KEEP_SHARE or box_gap_km(main_box, bbox(ring)) <= KEEP_NEAR_KM:
            kept.append((area, ring))
    return kept, sum(a for a, _ in kept)


def simplify(points, tol):
    """Douglas-Peucker, iterative."""
    if len(points) < 4:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        s, e = stack.pop()
        ax, ay = points[s]
        bx, by = points[e]
        dx, dy = bx - ax, by - ay
        norm = math.hypot(dx, dy)
        best, idx = 0.0, -1
        for i in range(s + 1, e):
            px, py = points[i]
            if norm == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / norm
            if d > best:
                best, idx = d, i
        if best > tol and idx > 0:
            keep[idx] = True
            stack.append((s, idx))
            stack.append((idx, e))
    return [p for p, k in zip(points, keep) if k]


def encode(points, precision=1e4):
    """Google encoded polyline, latitude first."""
    out = []
    plat = plon = 0
    for lon, lat in points:
        ilat = int(round(lat * precision))
        ilon = int(round(lon * precision))
        for delta in (ilat - plat, ilon - plon):
            v = ~(delta << 1) if delta < 0 else delta << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        plat, plon = ilat, ilon
    return "".join(out)


def shapes_for(kept):
    lines = []
    for _, ring in kept:
        pts = simplify(ring, SIMPLIFY_DEG)
        if len(pts) >= 4:
            lines.append(encode(pts))
    return lines


def rounded_box(b):
    return [round(b[0], 3), round(b[1], 3), round(b[2], 3), round(b[3], 3)]


def clean(name):
    return " ".join((name or "").split())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(os.path.expanduser("~"), ".cache", "currents-regions"))
    args = ap.parse_args()

    admin0 = fetch(args.cache, "admin0")
    admin1 = fetch(args.cache, "admin1")

    countries = {}
    shapes = {}
    for feat in admin0["features"]:
        p = feat["properties"]
        code = p.get("ADM0_A3")
        if not code or code == "-99":
            continue
        kept, area = main_parts(outer_rings(feat["geometry"]))
        if not kept:
            continue
        box = bbox(kept[0][1])
        for _, ring in kept[1:]:
            box = union(box, bbox(ring))
        iso =p.get("ISO_A2_EH") or p.get("ISO_A2") or ""
        countries[code] = {
            "id": code,
            "iso": "" if iso == "-99" else iso,
            "n": clean(p.get("ADMIN") or p.get("NAME_LONG")),
            "b": rounded_box(box),
            "a": int(round(area)),
        }
        shapes[code] = shapes_for(kept)

    regions = []
    seen = set()
    for feat in admin1["features"]:
        p = feat["properties"]
        rid = p.get("adm1_code")
        country = p.get("adm0_a3")
        name = clean(p.get("name_en") or p.get("name"))
        if not rid or rid in seen or not name or country not in countries:
            continue
        kept, area = main_parts(outer_rings(feat["geometry"]))
        if not kept or area < 1:
            continue
        seen.add(rid)
        box = bbox(kept[0][1])
        for _, ring in kept[1:]:
            box = union(box, bbox(ring))
        entry = {
            "id": rid,
            "c": country,
            "n": name,
            "t": clean(p.get("type_en") or p.get("type") or "").split("|")[0],
            "b": rounded_box(box),
            "a": int(round(area)),
        }
        local = clean(p.get("name"))
        if local and local != name:
            entry["m"] = local    # the local name, for search
        regions.append(entry)
        shapes[rid] = shapes_for(kept)

    # Countries with no first-level regions still get offered on their own.
    with_regions = {r["c"] for r in regions}
    country_list = sorted(countries.values(), key=lambda c: c["n"])
    for c in country_list:
        c["r"] = sum(1 for r in regions if r["c"] == c["id"]) if c["id"] in with_regions else 0
    regions.sort(key=lambda r: (r["c"], r["n"]))

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "offline_regions.json"), "w", encoding="utf-8") as f:
        json.dump({"version": 1, "source": SOURCE, "countries": country_list, "regions": regions},
                  f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(OUT_DIR, "offline_regions_shapes.json"), "w", encoding="utf-8") as f:
        json.dump({"version": 1, "source": SOURCE, "precision": 10000, "shapes": shapes},
                  f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(country_list)} countries, {len(regions)} regions", file=sys.stderr)


if __name__ == "__main__":
    main()
