#!/usr/bin/env python3
"""
Generate flat per-species fish illustrations (Catchr style) for free.

No public database of consistent flat fish illustrations exists, so we
generate them with Pollinations.ai — a free, no-key image API (Flux/SDXL).
Each species gets a side-profile flat illustration in one consistent style,
keyed on its common + scientific name. Output is a transparent PNG at 160px
that replaces the collection artwork; the app greys it out until caught.

The job is RESUMABLE: species that already have a PNG imageset are skipped,
so if Pollinations rate-limits or the CI run times out, just re-run the
workflow and it continues where it left off.

Usage
-----
    pip install requests pillow
    python scripts/generate_fish_art.py            # all missing
    python scripts/generate_fish_art.py --limit 400
    python scripts/generate_fish_art.py --force    # regenerate everything
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
from io import BytesIO
from pathlib import Path

import requests
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SEED_JSON = REPO / "ios/Currents/Resources/Data/species_seed.json"
ASSET_DIR = REPO / "ios/Currents/Resources/Assets.xcassets/Fish"

OUT_PX = 160
GEN_PX = 384  # generate larger, downscale for crisp edges

STYLE = (
    "flat minimalist vector illustration, side profile, full body, single fish, "
    "centered, clean simple shapes, smooth muted natural colors, soft shading, "
    "plain solid white background, sticker style, no text, no watermark, "
    "childrens field-guide illustration"
)


def prompt_for(sp: dict) -> str:
    common = sp.get("commonName", "").strip()
    sci = sp.get("scientificName", "").strip()
    subject = f"a {common} fish ({sci})" if common else f"a {sci} fish"
    return f"{subject}, {STYLE}"


def pollinations_url(prompt: str, seed: int) -> str:
    enc = urllib.parse.quote(prompt, safe="")
    return (
        f"https://image.pollinations.ai/prompt/{enc}"
        f"?width={GEN_PX}&height={GEN_PX}&seed={seed}&model=flux&nologo=true&enhance=false"
    )


def key_white_to_transparent(img: Image.Image) -> Image.Image:
    """Flood the near-white background to transparent from the borders."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    from collections import deque
    seen = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))

    def is_bg(r, g, b):
        return r > 238 and g > 238 and b > 238

    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y][x]:
            continue
        seen[y][x] = True
        r, g, b, a = px[x, y]
        if not is_bg(r, g, b):
            continue
        px[x, y] = (r, g, b, 0)
        q.append((x + 1, y)); q.append((x - 1, y))
        q.append((x, y + 1)); q.append((x, y - 1))
    return img


def write_imageset(species_id: int, img: Image.Image) -> None:
    imageset = ASSET_DIR / f"fish_{species_id}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    # Remove any prior JPEG (photo) asset.
    for old in imageset.glob("*.jpg"):
        old.unlink()
    filename = f"fish_{species_id}.png"
    img.save(imageset / filename, "PNG", optimize=True)
    contents = {
        "images": [{"filename": filename, "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "original"},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2))


def has_png(species_id: int) -> bool:
    return (ASSET_DIR / f"fish_{species_id}.imageset" / f"fish_{species_id}.png").exists()


def generate_one(sp: dict, force: bool) -> bool:
    sid = int(sp["id"])
    if has_png(sid) and not force:
        return True
    url = pollinations_url(prompt_for(sp), seed=1000 + sid)
    for attempt in range(4):
        try:
            r = requests.get(url, timeout=120)
            if r.status_code == 200 and r.headers.get("content-type", "").startswith("image"):
                img = Image.open(BytesIO(r.content)).convert("RGB")
                img = key_white_to_transparent(img)
                img = img.resize((OUT_PX, OUT_PX), Image.LANCZOS)
                write_imageset(sid, img)
                return True
            wait = 3 * (attempt + 1)
        except Exception:  # noqa: BLE001
            wait = 5 * (attempt + 1)
        time.sleep(wait)
    print(f"  ! failed fish_{sid} ({sp.get('commonName')})")
    return False


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="max to generate this run (0 = all)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--delay", type=float, default=1.5, help="polite delay between requests (s)")
    args = ap.parse_args()

    species = json.loads(SEED_JSON.read_text())
    todo = [s for s in species if args.force or not has_png(int(s["id"]))]
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(species)} species; {len(todo)} to generate this run.")

    done = 0
    for i, sp in enumerate(todo, start=1):
        if generate_one(sp, args.force):
            done += 1
        if i % 25 == 0:
            print(f"  {i}/{len(todo)} processed ({done} ok)")
        time.sleep(args.delay)

    remaining = sum(1 for s in species if not has_png(int(s["id"])))
    print(f"Done: {done} generated. {remaining} still missing "
          f"(re-run the workflow to continue).")


if __name__ == "__main__":
    main()
