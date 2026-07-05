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

Both providers use Google's Gemini 2.5 Flash Image ("Nano Banana"), which does
image-EDIT (image in, image out) — the illustration stays accurate because it
redraws the real photo. Provider is chosen by which key is set:
  * GEMINI_API_KEY    → Google's native API directly (free tier ~500 img/day, $0)
  * OPENROUTER_API_KEY→ same model via OpenRouter (paid, ~$0.039/img)
GEMINI_API_KEY wins if both are present.

The job is RESUMABLE: species that already have a PNG imageset are skipped, so
if the API rate-limits, hits the daily free quota, or the CI run times out, just
re-run the workflow and it continues where it left off.

Env
---
    GEMINI_API_KEY       Google AI Studio key (free tier) — preferred
    OPENROUTER_API_KEY   OpenRouter key (paid fallback)
    GEMINI_MODEL         optional — default "gemini-2.5-flash-image"
    OR_MODEL             optional — default "google/gemini-2.5-flash-image"
    OR_ASPECT            optional — OpenRouter image_config aspect_ratio (e.g. "1:1")

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

OUT_PX = 320  # match the batch pipeline so the collection stays uniform

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
OR_MODEL = os.environ.get("OR_MODEL") or "google/gemini-2.5-flash-image"
OR_ASPECT = os.environ.get("OR_ASPECT", "").strip()

GEMINI_MODEL = os.environ.get("GEMINI_MODEL") or "gemini-2.5-flash-image"
GEMINI_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)


class QuotaExceeded(Exception):
    """Raised on HTTP 429 — the daily free-tier quota is spent; stop and resume later."""

# img2img: redraw the REAL reference photo as a polished FLAT CARTOON icon (the
# clean simplified look of a modern fishing app's species art), while keeping the
# species accurate.
INSTRUCTION = (
    "Redraw this exact fish species as a polished flat cartoon vector "
    "illustration, in the clean modern style of a mobile fishing app's species "
    "icon. Use bold simplified shapes, smooth flat color fills, only minimal soft "
    "shading, a clean crisp outline, and a simple friendly cartoon eye. Keep the "
    "real species' body shape, proportions, fin placement, colours and key "
    "markings recognisable and accurate, but stylised and simplified — NOT "
    "photorealistic, no fine texture, no photographic detail, no gradients, no "
    "realistic scales. One whole single fish in side profile, head on the LEFT "
    "and tail on the RIGHT, on a plain solid pure-white background that fills "
    "the whole canvas. No text, no hook, no hands, no water, no shadow, no "
    "border, no frame, and no circle, oval, badge or sticker shape behind the "
    "fish."
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


def fetch_ref_bytes(ref: str) -> tuple[bytes, str]:
    """Download the reference photo so it can be sent inline to Gemini."""
    r = requests.get(ref, timeout=60)
    r.raise_for_status()
    mime = (r.headers.get("content-type", "") or "").split(";")[0].strip()
    if not mime.startswith("image"):
        mime = "image/jpeg"
    return r.content, mime


def gemini_edit(prompt: str, ref: str, api_key: str) -> Image.Image | None:
    """Google's native Gemini API in edit mode: prompt + reference photo in,
    redrawn image out. Raises QuotaExceeded on 429 (daily free-tier limit)."""
    raw, mime = fetch_ref_bytes(ref)
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": mime,
                                     "data": base64.b64encode(raw).decode()}},
                ],
            }
        ],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }
    r = requests.post(
        GEMINI_URL.format(model=GEMINI_MODEL),
        params={"key": api_key},
        json=payload,
        timeout=180,
    )
    if r.status_code == 429:
        raise QuotaExceeded(r.text[:180])
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:180]}")
    data = r.json()
    for cand in data.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                blob = base64.b64decode(inline["data"])
                return Image.open(BytesIO(blob)).convert("RGB")
    raise RuntimeError(f"no image in response: {json.dumps(data)[:180]}")


def edit_image(prompt: str, ref: str, api_key: str, provider: str) -> Image.Image | None:
    if provider == "gemini":
        return gemini_edit(prompt, ref, api_key)
    return openrouter_edit(prompt, ref, api_key)


def key_background_to_transparent(img: Image.Image) -> Image.Image:
    """Flood the background to transparent from the borders.

    The prompt asks for a pure-white background but the model occasionally
    returns grey, black or tinted backdrops (fish 138 shipped with a solid
    black one, 166 with grey). Instead of only keying near-white, sample the
    border to find the dominant background colour and flood anything close to
    it — plus the classic near-white anti-aliased halo — stopping at the fish.

    White-body safeguard: a silvery/white fish on a white backdrop matches the
    aggressive criteria itself, so the flood can eat the body straight through
    the anti-aliased outline. If the aggressive key leaves almost nothing
    behind, re-key with a strict near-white-only rule and keep that result
    when it preserves a plausible fish silhouette.
    """
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size

    # Dominant border colour = per-channel median of the edge pixels.
    border = (
        [px[x, 0] for x in range(w)] + [px[x, h - 1] for x in range(w)]
        + [px[0, y] for y in range(h)] + [px[w - 1, y] for y in range(h)]
    )
    def median(vals):
        vals = sorted(vals)
        return vals[len(vals) // 2]
    bg = (median([p[0] for p in border]),
          median([p[1] for p in border]),
          median([p[2] for p in border]))

    def is_bg(r, g, b):
        # Near the dominant border colour (handles white/grey/black/tinted
        # backdrops)…
        if abs(r - bg[0]) <= 32 and abs(g - bg[1]) <= 32 and abs(b - bg[2]) <= 32:
            return True
        # …the light anti-aliased halo (kills the white "sticker ring")…
        if r > 230 and g > 230 and b > 230:
            return True
        # …and light low-saturation pixels, so the flood can cross the
        # grey→white gradient where a white sticker disc meets a grey backdrop
        # (fish 166). The fish itself is protected by its darker crisp outline
        # and by connectivity — only border-connected pixels are removed.
        return (max(r, g, b) - min(r, g, b)) <= 24 and (r + g + b) >= 450

    aggressive = _flood_key(img, is_bg)
    if _opaque_fraction(aggressive) >= 0.12:
        return aggressive

    # Aggressive key ate (nearly) the whole canvas — the fish body itself
    # must match the light-low-sat / near-bg rules (white belly, silver
    # flanks). Retry keying strictly near-white; only the true backdrop
    # qualifies then.
    white_only = _flood_key(img, lambda r, g, b: r > 240 and g > 240 and b > 240)
    frac = _opaque_fraction(white_only)
    if 0.10 <= frac <= 0.80:
        return white_only
    return aggressive


def _flood_key(img: Image.Image, is_bg) -> Image.Image:
    """Border-connected flood: make every pixel reachable from the image edge
    that satisfies `is_bg` transparent. Returns a new RGBA image."""
    from collections import deque

    out = img.copy()
    px = out.load()
    w, h = out.size

    seen = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))

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
    return out


def _opaque_fraction(img: Image.Image) -> float:
    """Fraction of pixels still at least half-opaque — detects a keyed-away fish."""
    hist = img.getchannel("A").histogram()
    total = img.size[0] * img.size[1]
    return sum(hist[128:]) / total if total else 0.0


# Backwards-compatible alias (fish_art_batch.py and older callers).
key_white_to_transparent = key_background_to_transparent


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


def generate_one(sp: dict, force: bool, api_key: str, provider: str) -> bool:
    sid = int(sp["id"])
    if has_png(sid) and not force:
        return True
    ref = ref_url(sp)
    last: Image.Image | None = None
    for attempt in range(4):
        try:
            raw = edit_image(INSTRUCTION, ref, api_key, provider)
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
        except QuotaExceeded:
            raise  # stop the whole run; resume when quota resets
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
    ap.add_argument("--delay", type=float, default=0.0, help="delay between requests (s); 0 = auto per provider")
    ap.add_argument("--ids", type=str, default="", help="comma-separated species ids to (re)generate for testing")
    args = ap.parse_args()

    gem = os.environ.get("GEMINI_API_KEY", "").strip()
    orr = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if gem:
        provider, api_key = "gemini", gem
        print(f"Provider: Gemini native (free tier) — model {GEMINI_MODEL}")
    elif orr:
        provider, api_key = "openrouter", orr
        print(f"Provider: OpenRouter — model {OR_MODEL} (aspect={OR_ASPECT or 'default'})")
    else:
        raise SystemExit("Set GEMINI_API_KEY (free tier) or OPENROUTER_API_KEY as a GitHub secret.")

    # Free Gemini tier allows ~15 req/min; pace to stay under it.
    delay = args.delay if args.delay else (4.5 if provider == "gemini" else 1.5)

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
        try:
            if generate_one(sp, force, api_key, provider):
                done += 1
        except QuotaExceeded as e:
            print(f"Daily free-tier quota reached after {done} — resume when it "
                  f"resets (re-run the workflow). {e}")
            break
        if i % 25 == 0:
            print(f"  {i}/{len(todo)} processed ({done} ok)")
        time.sleep(delay)

    remaining = sum(1 for s in species if not has_png(int(s["id"])))
    print(f"Done: {done} generated. {remaining} still missing "
          f"(re-run the workflow to continue).")


if __name__ == "__main__":
    main()
