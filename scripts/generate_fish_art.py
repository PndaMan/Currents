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
from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parents[1]
SEED_JSON = REPO / "ios/Currents/Resources/Data/species_seed.json"
ASSET_DIR = REPO / "ios/Currents/Resources/Assets.xcassets/Fish"

OUT_PX = 160
GEN_PX = 384  # generate larger, downscale for crisp edges

STYLE = (
    "flat 2D vector illustration in the style of a modern mobile fishing app, "
    "side profile facing left, whole fish, single fish only, centered, "
    "smooth flat color fields with clean gentle cel shading, crisp clean outline, "
    "simple and stylized yet anatomically accurate fins body shape and proportions, "
    "true-to-life species markings and natural coloration, "
    "plain solid white background, sticker style, no text, no watermark, no border, "
    "no fishing hook, no water"
)


def prompt_for(sp: dict) -> str:
    common = sp.get("commonName", "").strip()
    sci = sp.get("scientificName", "").strip()
    # Lead with the scientific name for species accuracy.
    subject = f"{sci}" + (f", the {common}," if common else "")
    return f"{subject} fish, {STYLE}"


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


def facing_right(img: Image.Image) -> bool:
    """Detect head side by finding the EYE — the strongest dark-on-bright
    local contrast in the upper-front head zone. Validated to correctly tell
    left- from right-facing fish (a flared tail fools a simple centroid).
    Returns True if the head is on the right, so it should be flipped to face
    left for a consistent set (like Catchr)."""
    img = img.convert("RGBA")
    bbox = img.getchannel("A").getbbox()
    if not bbox:
        return False
    fish = img.crop(bbox)
    w, h = fish.size
    if w < 8 or h < 8:
        return False
    gray = fish.convert("L")
    mx = gray.filter(ImageFilter.MaxFilter(5))
    mn = gray.filter(ImageFilter.MinFilter(5))
    gp = gray.load()
    mxp = mx.load()
    mnp = mn.load()
    ap = fish.getchannel("A").load()

    def eye_score(x0: int, x1: int) -> int:
        best = 0
        for y in range(0, int(h * 0.62)):
            for x in range(x0, x1):
                if ap[x, y] < 120:
                    continue
                contrast = mxp[x, y] - mnp[x, y]
                if gp[x, y] < 90 and contrast > 70:
                    s = contrast + (120 - gp[x, y])
                    if s > best:
                        best = s
        return best

    left = eye_score(0, int(w * 0.38))
    right = eye_score(int(w * 0.62), w)
    return right > left


def is_low_quality(img: Image.Image) -> bool:
    """Reject near-black or near-greyscale renders (the 'dark crappie' failure)."""
    rgb = img.convert("RGB").resize((48, 48))
    a = img.getchannel("A").resize((48, 48))
    rp = rgb.load()
    ap = a.load()
    lum = sat = 0.0
    n = 0
    for y in range(48):
        for x in range(48):
            if ap[x, y] > 25:
                r, g, b = rp[x, y]
                lum += (r + g + b) / 3
                sat += max(r, g, b) - min(r, g, b)
                n += 1
    if n < 60:  # almost nothing drawn
        return True
    return (lum / n) < 48 or (sat / n) < 12


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
    prompt = prompt_for(sp)
    last: Image.Image | None = None
    for attempt in range(4):
        seed = 1000 + sid + attempt * 7919  # vary seed on retry
        try:
            r = requests.get(pollinations_url(prompt, seed), timeout=45)
            ctype = r.headers.get("content-type", "")
            if r.status_code == 200 and ctype.startswith("image"):
                img = Image.open(BytesIO(r.content)).convert("RGB")
                img = key_white_to_transparent(img)
                if facing_right(img):
                    img = img.transpose(Image.FLIP_LEFT_RIGHT)  # force facing-left
                last = img
                # Accept when the render is good, or on the final attempt.
                if not is_low_quality(img) or attempt == 3:
                    write_imageset(sid, img.resize((OUT_PX, OUT_PX), Image.LANCZOS))
                    print(f"  ok fish_{sid} {sp.get('commonName')} (attempt {attempt+1})")
                    return True
                print(f"  redo fish_{sid}: low-quality render, retrying")
            else:
                print(f"  retry fish_{sid}: HTTP {r.status_code} {ctype} (attempt {attempt+1})")
        except Exception as e:  # noqa: BLE001
            print(f"  retry fish_{sid}: {type(e).__name__} (attempt {attempt+1})")
        time.sleep(3 * (attempt + 1))
    if last is not None:
        write_imageset(sid, last.resize((OUT_PX, OUT_PX), Image.LANCZOS))
        return True
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
