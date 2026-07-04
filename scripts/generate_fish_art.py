#!/usr/bin/env python3
"""
Generate flat per-species fish illustrations (Catchr style).

No public database of consistent flat fish illustrations exists, so we
generate them with an image-EDIT model via OpenRouter's unified image API:
each species' REAL reference photo (iNaturalist / bundled thumbnail) is fed in
and redrawn as a clean flat 2D vector fish, so the illustration stays accurate
to the actual species (text-to-image just invents a plausible fish). Output is
a transparent PNG at 160px that replaces the collection artwork; the app greys
it out until caught.

Model is `google/gemini-2.5-flash-image` (Nano Banana) by default — the image
model on OpenRouter that supports image-EDIT (image in, image out) through the
chat endpoint. Swappable via the OR_MODEL env var.

The job is RESUMABLE: species that already have a PNG imageset are skipped, so
if the API rate-limits or the CI run times out, just re-run the workflow and it
continues where it left off.

Env
---
    OPENROUTER_API_KEY   required — your OpenRouter key
    OR_MODEL             optional — default "google/gemini-2.5-flash-image"
    OR_ASPECT            optional — image_config aspect_ratio (e.g. "1:1"); off if unset

Usage
-----
    pip install requests pillow
    python scripts/generate_fish_art.py            # all missing
    python scripts/generate_fish_art.py --limit 400
    python scripts/generate_fish_art.py --force    # regenerate everything
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import time
from io import BytesIO
from pathlib import Path

import requests
from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parents[1]
SEED_JSON = REPO / "ios/Currents/Resources/Data/species_seed.json"
ASSET_DIR = REPO / "ios/Currents/Resources/Assets.xcassets/Fish"

OUT_PX = 160

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
OR_MODEL = os.environ.get("OR_MODEL") or "google/gemini-2.5-flash-image"
OR_ASPECT = os.environ.get("OR_ASPECT", "").strip()

# img2img: redraw the REAL reference photo so the species stays accurate.
INSTRUCTION = (
    "Redraw this exact fish as a clean flat 2D vector illustration in a modern "
    "fishing field-guide app style. Keep the real species body shape, fins, "
    "proportions, markings and natural colors accurate to the photo. Side "
    "profile facing left, whole single fish, smooth flat color fields with "
    "gentle shading, crisp clean outline, plain solid white background, sticker "
    "style, no text, no hook, no hands, no water, no background scenery."
)

# Reference photo: iNaturalist URL when present, else the bundled thumbnail on
# master (raw GitHub) for the original curated species.
GITHUB_RAW = (
    "https://raw.githubusercontent.com/PndaMan/Currents/master/"
    "ios/Currents/Resources/Assets.xcassets/Fish/fish_{id}.imageset/fish_{id}.jpg"
)


def ref_url(sp: dict) -> str:
    return (sp.get("imageUrl") or "").strip() or GITHUB_RAW.format(id=int(sp["id"]))


def openrouter_edit(prompt: str, ref: str, api_key: str) -> Image.Image | None:
    """Call OpenRouter's unified image API in edit mode: prompt + reference photo
    in, redrawn image out. Returns a PIL image, or None on failure."""
    payload = {
        "model": OR_MODEL,
        "modalities": ["image", "text"],
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": ref}},
                ],
            }
        ],
    }
    if OR_ASPECT:
        payload["image_config"] = {"aspect_ratio": OR_ASPECT}
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/PndaMan/Currents",
        "X-Title": "Currents Fish Art",
    }
    r = requests.post(OPENROUTER_URL, json=payload, headers=headers, timeout=180)
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:180]}")
    data = r.json()
    try:
        images = data["choices"][0]["message"]["images"]
        url = images[0]["image_url"]["url"]
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(f"no image in response: {json.dumps(data)[:180]}")
    if url.startswith("data:"):
        b64 = url.split(",", 1)[1]
        raw = base64.b64decode(b64)
    else:  # provider returned a plain URL
        raw = requests.get(url, timeout=90).content
    return Image.open(BytesIO(raw)).convert("RGB")


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


def generate_one(sp: dict, force: bool, api_key: str) -> bool:
    sid = int(sp["id"])
    if has_png(sid) and not force:
        return True
    ref = ref_url(sp)
    last: Image.Image | None = None
    for attempt in range(4):
        try:
            raw = openrouter_edit(INSTRUCTION, ref, api_key)
            if raw is not None:
                img = key_white_to_transparent(raw)
                if facing_right(img):
                    img = img.transpose(Image.FLIP_LEFT_RIGHT)  # force facing-left
                last = img
                # Accept when the render is good, or on the final attempt.
                if not is_low_quality(img) or attempt == 3:
                    write_imageset(sid, img.resize((OUT_PX, OUT_PX), Image.LANCZOS))
                    print(f"  ok fish_{sid} {sp.get('commonName')} (attempt {attempt+1})")
                    return True
                print(f"  redo fish_{sid}: low-quality render, retrying")
        except Exception as e:  # noqa: BLE001
            print(f"  retry fish_{sid}: {e} (attempt {attempt+1})")
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
    ap.add_argument("--ids", type=str, default="", help="comma-separated species ids to (re)generate for testing")
    args = ap.parse_args()

    api_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY is not set (add it as a GitHub secret).")
    print(f"Model: {OR_MODEL} (aspect={OR_ASPECT or 'default'})")

    species = json.loads(SEED_JSON.read_text())
    if args.ids:
        want = {int(x) for x in args.ids.split(",") if x.strip()}
        todo = [s for s in species if int(s["id"]) in want]
    else:
        todo = [s for s in species if args.force or not has_png(int(s["id"]))]
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(species)} species; {len(todo)} to generate this run.")

    force = args.force or bool(args.ids)  # --ids always regenerates
    done = 0
    for i, sp in enumerate(todo, start=1):
        if generate_one(sp, force, api_key):
            done += 1
        if i % 25 == 0:
            print(f"  {i}/{len(todo)} processed ({done} ok)")
        time.sleep(args.delay)

    remaining = sum(1 for s in species if not has_png(int(s["id"])))
    print(f"Done: {done} generated. {remaining} still missing "
          f"(re-run the workflow to continue).")


if __name__ == "__main__":
    main()
