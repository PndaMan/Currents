#!/usr/bin/env python3
"""
Generate one flat illustration per lure and bait key, in the same style as the
per-species fish art, for LureArtView (ios/Currents/Core/Theme/DS/LureArt.swift).

The keys come from the rule table in LureArt.swift, so the script and the app
can never disagree about which images exist. Each key has a hand-written
subject below; every prompt shares one style and one composition (side view,
front on the left, centred, plain white background), and one existing fish
illustration is attached as a style reference so lures and fish sit together.

Same model and providers as scripts/generate_fish_art.py: Google's Gemini 2.5
Flash Image, chosen by which key is set:
  * GEMINI_API_KEY      Google's API directly
  * OPENROUTER_API_KEY  the same model via OpenRouter
GEMINI_API_KEY wins if both are set.

Output: Resources/Assets.xcassets/Lures/lure_<key>.imageset/lure_<key>.png,
background keyed to transparent, object fitted to a square canvas. The job is
resumable: keys that already have an image are skipped unless --force or --keys.

Usage
-----
    uv run --with requests --with pillow scripts/generate_lure_art.py --dry-run
    uv run --with requests --with pillow scripts/generate_lure_art.py --keys spoon,worm
    uv run --with requests --with pillow scripts/generate_lure_art.py --variants 3
        # three candidates per key into the review folder, nothing in the app
    uv run --with requests --with pillow scripts/generate_lure_art.py --promote spoon=2
        # copy a reviewed candidate into the asset catalog (no API call)
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import tempfile
import time
from io import BytesIO
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LURE_ART_SWIFT = REPO / "ios/Currents/Core/Theme/DS/LureArt.swift"
ASSET_ROOT = REPO / "ios/Currents/Resources/Assets.xcassets"
ASSET_DIR = ASSET_ROOT / "Lures"
STYLE_REF_DIR = ASSET_ROOT / "Fish"
REVIEW_DIR = Path(tempfile.gettempdir()) / "currents-lure-art"

OUT_PX = 320     # same canvas as the fish art
FILL = 0.86      # longest side of the object as a share of the canvas
WORK_PX = 512    # key the background on a downscaled copy (fast)

GEMINI_MODEL = os.environ.get("GEMINI_MODEL") or "gemini-2.5-flash-image"
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
OR_MODEL = os.environ.get("OR_MODEL") or "google/gemini-2.5-flash-image"

# Prices in US dollars per generated image (1024 px, 1290 output tokens at
# $30 per million output tokens), checked 2026-10-22:
#   https://ai.google.dev/gemini-api/docs/pricing  (Gemini 2.5 Flash Image)
#   https://openrouter.ai/google/gemini-2.5-flash-image
PRICE_PER_IMAGE = 0.039
# Text and one reference image in: roughly 600 input tokens at $0.30 per million.
PRICE_INPUT_PER_REQUEST = 600 * 0.30 / 1_000_000

# Calls sent and dollars spent this run. OpenRouter reports the real cost of
# each call; the Gemini path counts the list price.
SPEND = {"calls": 0, "usd": 0.0}

STYLE = (
    "A polished flat cartoon vector illustration in the clean modern style of a "
    "mobile fishing app's icon set, matching the attached reference fish exactly: "
    "the same crisp dark outline weight, bold simplified shapes, smooth flat colour "
    "fills and only minimal soft shading. Not photorealistic, no fine texture, no "
    "photographic detail, no gradients. Do not draw the reference fish; draw only "
    "this subject: "
)

COMPOSITION = (
    " Draw one single subject, whole and uncropped, in side view with its front on "
    "the LEFT, centred, filling about 80 percent of the canvas width, on a plain "
    "solid pure-white background that fills the whole square canvas. No text, no "
    "logo, no brand name, no packaging, no hands, no rod, no water, no shadow, no "
    "border, no frame, and no circle, badge or sticker shape behind it."
)

# What to draw for each key in LureArt.swift. Colours are classic, natural
# patterns so each lure is recognisable at thumbnail size.
SUBJECTS = {
    "fly": "a classic streamer fly for fly fishing: one long-shank hook dressed with a flowing olive and white feather wing, a short red tail and a gold bead head, lying horizontally with the hook eye on the left.",
    "sabiki": "a short sabiki bait rig: a length of clear fishing line with three small gold hooks on short droppers, each dressed with a tiny pink and white shiny fish-skin flasher, a small swivel at one end and a small lead sinker at the other, lying horizontally.",
    "frog": "a hollow-body topwater frog lure: a soft green frog-shaped body with a yellow belly, a double hook curving up along its back and two rubber skirt legs trailing behind, head on the left.",
    "spinnerbait": "a spinnerbait lure: a V-shaped wire arm with a silver willow-leaf blade and a small gold round blade on the upper arm, and on the lower arm a lead head with a white and chartreuse silicone skirt and a single hook, head on the left.",
    "chatterbait": "a bladed swim jig (chatterbait): a lead jig head with a hexagonal silver vibrating blade clipped to its nose, a green pumpkin silicone skirt and a paddle-tail soft plastic trailer, head on the left.",
    "inline_spinner": "an inline spinner lure: a straight wire shaft with one silver oval blade at the front, a brass bead body, and a treble hook dressed with a red tuft at the back, line tie on the left.",
    "topwater": "a topwater walking bait: a long cigar-shaped hard plastic lure in bone white with a grey back and a red throat, two treble hooks underneath, nose on the left.",
    "lipless_crankbait": "a lipless crankbait (rattle bait): a flat, deep-bodied hard plastic baitfish shape with no diving lip, chrome sides and a blue back, the line tie on top of the head, two treble hooks underneath, head on the left.",
    "jerkbait": "a jerkbait (minnow plug): a long slim hard plastic minnow-shaped lure with a small clear diving lip, silver flanks and a dark green back, three treble hooks underneath, head on the left.",
    "swimbait": "a soft plastic paddle-tail swimbait: a soft shad-shaped body in pearl white with a light blue back and a round paddle tail, rigged on a lead jig head with a single upturned hook, head on the left.",
    "drop_shot": "a drop shot rig: a slim straight soft plastic finesse worm in natural brown, nose-hooked on a small hook tied to a vertical fishing line, with a small cylindrical lead weight hanging below on a short tag of line.",
    "ned_rig": "a ned rig: a short stubby soft plastic stick bait in green pumpkin on a mushroom-shaped lead jig head, the hook point exposed on top, head on the left.",
    "plastic_worm": "a Texas-rigged soft plastic worm: a long ribbed purple worm with a curly tail, rigged weedless on an offset worm hook, with a bullet-shaped sinker on the line in front of its head, head on the left.",
    "jigging_spoon": "a metal jigging spoon (vertical jig): a long slim slab of polished chrome metal, slightly curved, with an assist hook at the front and a treble hook at the back, lying horizontally with the line tie on the left.",
    "spoon": "a classic casting spoon lure: a curved teardrop-shaped metal blade, narrow at the front and broad and rounded at the back, polished gold with one red diagonal stripe, a split ring at the narrow front end and a treble hook hanging from the broad back end, lying horizontally with the narrow front on the left.",
    "crankbait": "a squarebill crankbait: a short chunky hard plastic body in chartreuse with a dark back and an orange belly, a square-cut clear diving lip at the front, two treble hooks underneath, head on the left.",
    "trolling_lure": "a skirted offshore trolling lure: a bullet-shaped resin head with a large eye, followed by a long flowing pink and blue vinyl skirt, one large hook inside the skirt, head on the left.",
    "soft_plastic": "a curly-tail grub soft plastic on a round lead jig head: a short ribbed body in motor-oil green with a long curly tail, the hook point exposed on top, head on the left.",
    "jig": "a skirted bass jig: a lead jig head with a fibre weed guard, a full flared silicone skirt in black and blue, and a craw-shaped soft plastic trailer behind it, head on the left.",
    "squid": "one small whole squid used as fishing bait: a pale pinkish-white body with fins at the pointed end and short tentacles, lying horizontally with the tentacles on the left.",
    "clam": "one opened clam in its shell showing the soft orange meat inside, used as fishing bait.",
    "sand_flea": "one sand flea (mole crab) used as fishing bait: a small egg-shaped sandy grey shell with short feathery antennae, seen from slightly above.",
    "crayfish": "one reddish-brown crayfish, claws forward on the left and tail on the right, seen from slightly above.",
    "crab": "one small crab with a sandy orange-brown shell, claws to the front, seen from slightly above.",
    "shrimp": "one whole raw prawn used as fishing bait, translucent pinkish grey, head and antennae on the left and tail fan on the right, slightly curled.",
    "salmon_eggs": "a small cluster of glossy round bright orange salmon eggs, as used for trout bait.",
    "worm": "one reddish-pink earthworm, gently curved in a soft S shape, lying horizontally.",
    "insect": "one brown cricket in side profile, head on the left, long antennae and folded jumping legs.",
    "corn": "a small heap of six bright yellow sweetcorn kernels.",
    "dough_bait": "three round dough bait balls (carp boilies) in pale yellow and orange, grouped together.",
    "bread": "one torn piece of white bread with a light golden crust.",
    "cut_bait": "one chunk of cut fish bait: a rectangular strip of fish fillet with silver skin on one side and pink flesh, cut cleanly at both ends, lying horizontally.",
    "baitfish": "one whole sardine baitfish, silver with a blue-green back, in side profile, head on the left.",
}


def lure_keys() -> list[str]:
    """Art keys in the order of the rule table in LureArt.swift."""
    src = LURE_ART_SWIFT.read_text()
    keys = re.findall(r'Rule\(key: "(\w+)"', src)
    if not keys:
        raise SystemExit(f"No Rule(key: ...) entries found in {LURE_ART_SWIFT}")
    missing = [k for k in keys if k not in SUBJECTS]
    extra = [k for k in SUBJECTS if k not in keys]
    if missing or extra:
        raise SystemExit(f"SUBJECTS out of sync with LureArt.swift. Missing: {missing} Extra: {extra}")
    return keys


def prompt_for(key: str) -> str:
    return STYLE + SUBJECTS[key] + COMPOSITION


def asset_name(key: str) -> str:
    return f"lure_{key}"


def has_png(key: str) -> bool:
    name = asset_name(key)
    return (ASSET_DIR / f"{name}.imageset" / f"{name}.png").exists()


# --- providers --------------------------------------------------------------

def style_ref_png(species_id: int) -> bytes:
    """An existing fish illustration flattened onto white, as the style anchor."""
    from PIL import Image

    path = STYLE_REF_DIR / f"fish_{species_id}.imageset" / f"fish_{species_id}.png"
    fish = Image.open(path).convert("RGBA")
    flat = Image.new("RGB", fish.size, (255, 255, 255))
    flat.paste(fish, (0, 0), fish)
    buf = BytesIO()
    flat.save(buf, "PNG")
    return buf.getvalue()


def gemini_generate(prompt: str, ref: bytes | None, api_key: str):
    import requests
    from PIL import Image
    from generate_fish_art import QuotaExceeded

    parts: list[dict] = [{"text": prompt}]
    if ref:
        parts.append({"inline_data": {"mime_type": "image/png", "data": base64.b64encode(ref).decode()}})
    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }
    # Header, not a query parameter, so the key never appears in an error message.
    r = requests.post(GEMINI_URL.format(model=GEMINI_MODEL), headers={"x-goog-api-key": api_key},
                      json=payload, timeout=180)
    SPEND["calls"] += 1
    SPEND["usd"] += PRICE_PER_IMAGE + PRICE_INPUT_PER_REQUEST
    if r.status_code == 429:
        raise QuotaExceeded(r.text[:180])
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:180]}")
    data = r.json()
    for cand in data.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                return Image.open(BytesIO(base64.b64decode(inline["data"]))).convert("RGB")
    raise RuntimeError(f"no image in response: {json.dumps(data)[:180]}")


def openrouter_generate(prompt: str, ref: bytes | None, api_key: str):
    import requests
    from PIL import Image
    from generate_fish_art import QuotaExceeded

    content: list[dict] = [{"type": "text", "text": prompt}]
    if ref:
        url = "data:image/png;base64," + base64.b64encode(ref).decode()
        content.append({"type": "image_url", "image_url": {"url": url}})
    payload = {
        "model": OR_MODEL,
        "modalities": ["image", "text"],
        "messages": [{"role": "user", "content": content}],
        "image_config": {"aspect_ratio": "1:1"},
        "usage": {"include": True},
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/PndaMan/Currents",
        "X-Title": "Currents Lure Art",
    }
    r = requests.post(OPENROUTER_URL, json=payload, headers=headers, timeout=180)
    SPEND["calls"] += 1
    if r.status_code in (402, 429):  # out of credit or key limit, or rate limited: stop
        raise QuotaExceeded(f"HTTP {r.status_code}: {r.text[:180]}")
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:180]}")
    data = r.json()
    cost = (data.get("usage") or {}).get("cost")
    SPEND["usd"] += float(cost) if cost is not None else PRICE_PER_IMAGE + PRICE_INPUT_PER_REQUEST
    try:
        url = data["choices"][0]["message"]["images"][0]["image_url"]["url"]
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(f"no image in response: {json.dumps(data)[:180]}")
    raw = base64.b64decode(url.split(",", 1)[1]) if url.startswith("data:") else requests.get(url, timeout=90).content
    return Image.open(BytesIO(raw)).convert("RGB")


# --- post-processing --------------------------------------------------------

def post_process(raw):
    """White background to transparent (the fish pipeline's keyer), then crop to
    the object and fit it on a square transparent canvas at a uniform scale.
    Returns None for a near-empty render."""
    from PIL import Image
    from generate_fish_art import key_background_to_transparent

    work = raw.copy()
    work.thumbnail((WORK_PX, WORK_PX), Image.LANCZOS)
    keyed = key_background_to_transparent(work)
    bbox = keyed.getchannel("A").getbbox()
    if not bbox:
        return None
    obj = keyed.crop(bbox)
    alpha = obj.getchannel("A").histogram()
    if sum(alpha[128:]) < 0.005 * WORK_PX * WORK_PX:
        return None
    box = int(OUT_PX * FILL)
    scale = box / max(obj.width, obj.height)
    obj = obj.resize((max(1, round(obj.width * scale)), max(1, round(obj.height * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (OUT_PX, OUT_PX), (0, 0, 0, 0))
    canvas.paste(obj, ((OUT_PX - obj.width) // 2, (OUT_PX - obj.height) // 2), obj)
    return canvas


def write_imageset(key: str, img) -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    folder_contents = ASSET_DIR / "Contents.json"
    if not folder_contents.exists():
        folder_contents.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    name = asset_name(key)
    imageset = ASSET_DIR / f"{name}.imageset"
    imageset.mkdir(exist_ok=True)
    img.save(imageset / f"{name}.png", "PNG", optimize=True)
    contents = {
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "original"},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2))


def contact_sheet(paths: list[Path], out: Path) -> None:
    """Every candidate on light and dark plates, so the set can be judged as one."""
    from PIL import Image

    cell = 160
    cols = 6
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * cell * 2), (255, 255, 255))
    for i, p in enumerate(paths):
        img = Image.open(p).convert("RGBA").resize((cell - 16, cell - 16), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * cell * 2
        for j, plate in enumerate(((230, 230, 230), (38, 38, 38))):
            sheet.paste(Image.new("RGB", (cell, cell), plate), (x, y + j * cell))
            sheet.paste(img, (x + 8, y + j * cell + 8), img)
    sheet.save(out)


# --- commands ---------------------------------------------------------------

def dry_run(todo: list[str], variants: int, style_ref: int) -> None:
    for key in todo:
        print(f"--- {asset_name(key)}\n{prompt_for(key)}\n")
    n = len(todo) * variants
    per = PRICE_PER_IMAGE + PRICE_INPUT_PER_REQUEST
    print(f"Style reference: fish_{style_ref} (attached to every request; 0 = none)")
    print(f"{len(todo)} keys x {variants} variant(s) = {n} images")
    print(f"Estimated cost: {n} x ${PRICE_PER_IMAGE:.3f} per image + input "
          f"= ${n * per:.2f} (Gemini 2.5 Flash Image, standard rate)")
    print("No request was sent.")


def promote(spec: str) -> None:
    from PIL import Image

    key, _, index = spec.partition("=")
    if key not in lure_keys():
        raise SystemExit(f"Unknown key {key!r}")
    src = REVIEW_DIR / f"{key}_{index}.png"
    if not src.exists():
        raise SystemExit(f"No candidate at {src}")
    write_imageset(key, Image.open(src).convert("RGBA"))
    print(f"Promoted {src.name} to {asset_name(key)}")


def sheet_of_catalog() -> None:
    """Contact sheet of every key's current asset, in rule order (no API call)."""
    keys = lure_keys()
    paths = [ASSET_DIR / f"{asset_name(k)}.imageset" / f"{asset_name(k)}.png" for k in keys]
    missing = [k for k, p in zip(keys, paths) if not p.exists()]
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)
    out = REVIEW_DIR / "catalog_sheet.png"
    contact_sheet([p for p in paths if p.exists()], out)
    print(f"{len(keys) - len(missing)}/{len(keys)} keys have art. Missing: {missing or 'none'}")
    print(f"Sheet: {out}")


def generate(todo: list[str], variants: int, style_ref: int, delay: float, budget: float) -> None:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from generate_fish_art import QuotaExceeded

    gem = os.environ.get("GEMINI_API_KEY", "").strip()
    orr = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if gem:
        provider, api_key, call = f"Gemini {GEMINI_MODEL}", gem, gemini_generate
    elif orr:
        provider, api_key, call = f"OpenRouter {OR_MODEL}", orr, openrouter_generate
    else:
        raise SystemExit("Set GEMINI_API_KEY or OPENROUTER_API_KEY.")
    print(f"Provider: {provider}. {len(todo)} keys x {variants} variant(s). Budget ${budget:.2f}.")

    ref = style_ref_png(style_ref) if style_ref else None
    raw_dir = REVIEW_DIR / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    review: list[Path] = []
    next_call = PRICE_PER_IMAGE + PRICE_INPUT_PER_REQUEST

    def over_budget() -> bool:
        return SPEND["usd"] + next_call > budget

    for key in todo:
        for v in range(1, variants + 1):
            img = None
            for attempt in range(3):
                if over_budget():
                    break
                try:
                    raw = call(prompt_for(key), ref, api_key)
                    raw.save(raw_dir / f"{key}_{v}_{attempt + 1}.png")
                    img = post_process(raw)
                    if img is not None:
                        break
                    print(f"  redo {key}: empty render")
                except QuotaExceeded as e:
                    print(f"Quota or credit limit reached; re-run later to continue. {e}")
                    return
                except Exception as e:  # noqa: BLE001
                    print(f"  retry {key}: {e} (attempt {attempt + 1})")
                time.sleep(3 * (attempt + 1))
            if over_budget() and img is None:
                print(f"Budget reached after {SPEND['calls']} calls (${SPEND['usd']:.3f}); stopping.")
                return
            if img is None:
                print(f"  ! failed {key}")
                break
            if variants > 1:
                path = REVIEW_DIR / f"{key}_{v}.png"
                img.save(path)
                review.append(path)
                print(f"  candidate {path}")
            else:
                write_imageset(key, img)
                print(f"  ok {asset_name(key)}")
            print(f"    spend so far: {SPEND['calls']} calls, ${SPEND['usd']:.4f}")
            time.sleep(delay)

    if review:
        sheet = REVIEW_DIR / "contact_sheet.png"
        contact_sheet(review, sheet)
        print(f"Review {sheet}, then: --promote <key>=<n>")
    print(f"Done: {SPEND['calls']} calls, ${SPEND['usd']:.4f}.")


def main() -> None:
    global REVIEW_DIR
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="print prompts and the cost estimate; send nothing")
    ap.add_argument("--keys", default="", help="comma-separated keys to (re)generate")
    ap.add_argument("--force", action="store_true", help="regenerate keys that already have art")
    ap.add_argument("--variants", type=int, default=1, help="candidates per key; >1 writes to the review folder")
    ap.add_argument("--style-ref", type=int, default=1, help="species id of the fish art used as style reference (0 = none)")
    ap.add_argument("--delay", type=float, default=4.5, help="seconds between requests")
    ap.add_argument("--budget", type=float, default=5.0, help="stop before spending more than this many dollars")
    ap.add_argument("--review-dir", default=str(REVIEW_DIR), help="where raw renders, candidates and sheets go")
    ap.add_argument("--promote", default="", help="key=n: copy review candidate n into the asset catalog")
    ap.add_argument("--sheet", action="store_true", help="contact sheet of the current catalog art; send nothing")
    args = ap.parse_args()
    REVIEW_DIR = Path(args.review_dir)

    if args.promote:
        promote(args.promote)
        return
    if args.sheet:
        sheet_of_catalog()
        return

    keys = lure_keys()
    if args.keys:
        want = [k.strip() for k in args.keys.split(",") if k.strip()]
        unknown = [k for k in want if k not in keys]
        if unknown:
            raise SystemExit(f"Unknown keys: {unknown}")
        todo = want
    else:
        todo = [k for k in keys if args.force or args.variants > 1 or not has_png(k)]

    if args.dry_run:
        dry_run(todo, max(1, args.variants), args.style_ref)
    else:
        generate(todo, max(1, args.variants), args.style_ref, args.delay, args.budget)


if __name__ == "__main__":
    main()
