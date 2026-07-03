#!/usr/bin/env python3
"""
Build the full Currents species dataset + collection artwork.

This runs on a machine WITH internet (the CI runner or a dev laptop) — the
app's own build sandbox has no outbound access to iNaturalist / FishBase, so
this is a data-prep step, not a build step.

What it does
------------
1. Pulls the most-observed ray-finned fishes (Actinopterygii, taxon 47178)
   from the iNaturalist taxa API, paging until it has TARGET_COUNT species.
2. Assigns a rarity tier (0 common … 4 legendary) from observation-count
   quantiles — the fish everyone catches are Common, the seldom-seen ones
   Legendary.
3. Downloads each species' default CC photo, produces a square colour
   thumbnail (used across the app; the app greys it out until caught).
4. Writes:
     - ios/Currents/Resources/Data/species_seed.json   (expanded, with rarityRank)
     - ios/Currents/Resources/Assets.xcassets/Fish/fish_<id>.imageset/*

Usage
-----
    pip install requests pillow
    python scripts/build_species_dataset.py --count 1500

Notes
-----
- iNaturalist photos are Creative Commons; attribution is written to
  docs/species_attribution.csv.
- Re-running is idempotent: existing thumbnails are skipped unless --force.
- If a species has no CC photo, no imageset is written and the app falls back
  to its silhouette automatically.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from pathlib import Path

try:
    import requests
    from PIL import Image
    from io import BytesIO
except ImportError:
    sys.exit("Missing deps. Run: pip install requests pillow")

INAT_TAXA = "https://api.inaturalist.org/v1/taxa"
ACTINOPTERYGII = 47178  # ray-finned fishes
THUMB_PX = 320

REPO = Path(__file__).resolve().parents[1]
SEED_JSON = REPO / "ios/Currents/Resources/Data/species_seed.json"
ASSET_DIR = REPO / "ios/Currents/Resources/Assets.xcassets/Fish"
ATTRIB_CSV = REPO / "docs/species_attribution.csv"

HABITAT_HINTS = {
    "marine": "marine",
    "brackish": "brackish",
    "freshwater": "freshwater",
}


def fetch_species(target: int) -> list[dict]:
    """Page iNaturalist taxa by observation count (desc)."""
    out: list[dict] = []
    page = 1
    per_page = 200
    while len(out) < target:
        resp = requests.get(
            INAT_TAXA,
            params={
                "taxon_id": ACTINOPTERYGII,
                "rank": "species",
                "order_by": "observations_count",
                "order": "desc",
                "per_page": per_page,
                "page": page,
                "locale": "en",
            },
            timeout=60,
        )
        resp.raise_for_status()
        results = resp.json().get("results", [])
        if not results:
            break
        for r in results:
            name = r.get("name")
            common = (r.get("preferred_common_name") or name or "").strip()
            if not name or not common:
                continue
            out.append(
                {
                    "scientificName": name,
                    "commonName": common.title(),
                    "family": _ancestor_family(r),
                    "observations": r.get("observations_count", 0),
                    "photo": (r.get("default_photo") or {}),
                }
            )
        page += 1
        time.sleep(0.6)  # be polite to the API
        print(f"  fetched {len(out)} species so far…")
    return out[:target]


def _ancestor_family(taxon: dict) -> str | None:
    for a in taxon.get("ancestors", []) or []:
        if a.get("rank") == "family":
            return a.get("name")
    return None


def assign_rarity(species: list[dict]) -> None:
    """Quantile the observation counts into 5 rarity tiers."""
    ordered = sorted(species, key=lambda s: s["observations"], reverse=True)
    n = len(ordered)
    # Common 45%, Uncommon 25%, Rare 18%, Epic 9%, Legendary 3%
    bounds = [0.45, 0.70, 0.88, 0.97, 1.01]
    for i, s in enumerate(ordered):
        frac = i / max(1, n)
        for rank, b in enumerate(bounds):
            if frac < b:
                s["rarityRank"] = rank
                break


def build_thumbnail(url: str, dest: Path, force: bool) -> bool:
    if dest.exists() and not force:
        return True
    try:
        # iNat "medium" is ~500px; bump to square_2048 if available
        big = url.replace("/square.", "/medium.").replace("/small.", "/medium.")
        data = requests.get(big, timeout=60).content
        img = Image.open(BytesIO(data)).convert("RGB")
        # center-crop to square, resize
        w, h = img.size
        side = min(w, h)
        img = img.crop(
            ((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2)
        ).resize((THUMB_PX, THUMB_PX), Image.LANCZOS)
        dest.parent.mkdir(parents=True, exist_ok=True)
        img.save(dest, "PNG", optimize=True)
        return True
    except Exception as e:  # noqa: BLE001
        print(f"    ! thumbnail failed for {dest.name}: {e}")
        return False


def write_imageset(species_id: int, png_path: Path) -> None:
    imageset = ASSET_DIR / f"fish_{species_id}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    filename = f"fish_{species_id}.png"
    (imageset / filename).write_bytes(png_path.read_bytes())
    contents = {
        "images": [{"filename": filename, "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "original"},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=1500)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--skip-images", action="store_true",
                    help="Only write species_seed.json, no artwork")
    args = ap.parse_args()

    print(f"Fetching up to {args.count} species from iNaturalist…")
    species = fetch_species(args.count)
    print(f"Got {len(species)} species. Assigning rarity…")
    assign_rarity(species)

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    (ASSET_DIR / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2)
    )

    seed: list[dict] = []
    attribution: list[tuple] = []
    tmp = REPO / "build/species_thumbs"

    for i, s in enumerate(species, start=1):
        entry = {
            "id": i,
            "scientificName": s["scientificName"],
            "commonName": s["commonName"],
            "family": s["family"],
            "habitat": "freshwater",  # refined by BaitSeedData / manual curation
            "minTempC": None,
            "maxTempC": None,
            "optimalTempC": None,
            "fishbaseId": None,
            "imageUrl": s["photo"].get("medium_url"),
            "rarityRank": s.get("rarityRank", 0),
        }
        seed.append(entry)

        if not args.skip_images:
            photo_url = s["photo"].get("square_url") or s["photo"].get("url")
            if photo_url:
                png = tmp / f"fish_{i}.png"
                if build_thumbnail(photo_url, png, args.force):
                    write_imageset(i, png)
                    attribution.append(
                        (i, s["commonName"], s["photo"].get("attribution", ""))
                    )
        if i % 50 == 0:
            print(f"  processed {i}/{len(species)}")

    SEED_JSON.write_text(json.dumps(seed, indent=2))
    print(f"Wrote {len(seed)} species → {SEED_JSON.relative_to(REPO)}")

    ATTRIB_CSV.parent.mkdir(parents=True, exist_ok=True)
    with ATTRIB_CSV.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["species_id", "common_name", "photo_attribution"])
        w.writerows(attribution)
    print(f"Wrote attribution for {len(attribution)} photos → {ATTRIB_CSV.relative_to(REPO)}")


if __name__ == "__main__":
    main()
