#!/usr/bin/env python3
"""
Generate fresh, simplistic app-icon CONCEPTS for Currents with Gemini 2.5 Flash
Image (Nano Banana). Text-to-image (no reference) — we're inventing a new mark,
so accuracy-to-a-photo doesn't apply.

Each concept is a single bold idea, centred, on a solid/gradient background,
1024x1024, no text — the recipe for a clean iOS icon that reads at small sizes.
Outputs land in design/app-icons/ for review; nothing is wired into the app until
one is chosen.

Env: GEMINI_API_KEY (paid tier).
Usage:
    python scripts/generate_app_icon.py            # all concepts
    python scripts/generate_app_icon.py --only 1,4 # just those concept numbers
"""

from __future__ import annotations

import argparse
import base64
import os
from io import BytesIO
from pathlib import Path

from google import genai
from google.genai import types
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
OUT_DIR = REPO / "design/app-icons"
MODEL = os.environ.get("GEMINI_MODEL") or "gemini-2.5-flash-image"

STYLE = (
    "Design a modern iOS app icon, flat minimalist vector style, one single bold "
    "simple idea, centred, clean geometric shapes, high contrast, smooth solid "
    "background that fills the whole square, no text, no letters, no words, no "
    "photorealism, crisp and simple so it reads at small sizes, app-store quality, "
    "1024x1024 square. The app is 'Currents', a fishing app. Concept: "
)

# Distinct, deliberately different directions — a fresh mark, not the tangled
# ribbons of the old icon.
CONCEPTS = {
    1: "a single clean minimalist fish silhouette in side profile facing left, "
       "warm cream-white, centred on a rich deep forest-green background.",
    2: "one simple fish drawn as a single continuous smooth monoline stroke, "
       "bright teal line on a deep navy-blue background.",
    3: "one elegant flowing water current — two smooth clean ribbon curves "
       "suggesting a wave, white on an ocean-blue gradient. Minimal, not busy.",
    4: "a minimalist rounded location map pin whose teardrop body holds a tiny "
       "simple fish cut-out, flat white on an emerald-green background.",
    5: "a simple stylised fish leaping over a single smooth wave, flat two-tone, "
       "white and pale teal on a deep blue background.",
    6: "a minimal fish hook curving elegantly into a small water ripple, soft "
       "gold on a dark teal background.",
    7: "a bold simple wave crest shaped subtly like a fish tail fin, white on a "
       "vivid cyan-to-blue gradient, very minimal.",
    8: "a single water droplet with a tiny fish silhouette inside it, flat, "
       "cream on deep green, extremely simple and iconic.",
}


def generate(concept_no: int, prompt: str, client: genai.Client) -> bool:
    for attempt in range(3):
        try:
            resp = client.models.generate_content(
                model=MODEL,
                contents=[types.Part(text=STYLE + prompt)],
                config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
            )
            for cand in resp.candidates or []:
                for part in (cand.content.parts if cand.content else []):
                    inline = getattr(part, "inline_data", None)
                    if inline and inline.data:
                        img = Image.open(BytesIO(inline.data)).convert("RGB")
                        img = img.resize((1024, 1024), Image.LANCZOS)
                        OUT_DIR.mkdir(parents=True, exist_ok=True)
                        img.save(OUT_DIR / f"concept_{concept_no}.png", "PNG")
                        print(f"  ok concept_{concept_no}")
                        return True
            print(f"  retry concept_{concept_no}: no image (attempt {attempt+1})")
        except Exception as e:  # noqa: BLE001
            print(f"  retry concept_{concept_no}: {e} (attempt {attempt+1})")
    print(f"  ! failed concept_{concept_no}")
    return False


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", type=str, default="", help="comma-separated concept numbers")
    args = ap.parse_args()

    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not key:
        raise SystemExit("GEMINI_API_KEY is not set.")
    client = genai.Client(api_key=key)

    want = {int(x) for x in args.only.split(",") if x.strip()} if args.only else set(CONCEPTS)
    for no in sorted(want):
        if no in CONCEPTS:
            generate(no, CONCEPTS[no], client)


if __name__ == "__main__":
    main()
