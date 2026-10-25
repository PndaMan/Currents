# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10.4"]
# ///
"""Frame raw App Store captures with a short headline.

Each raw capture (1320x2868, iPhone 16 Pro Max) becomes a 1320x2868 PNG: the
headline at the top in the system font, and the capture scaled down below it
with rounded corners, on the app's dark background.

Headlines come from a JSON file mapping a capture's file stem (for example
"01_today") to its headline. Captures without a headline are skipped.

    uv run scripts/frame_screenshots.py \
        --input ios/screenshots/6.9 \
        --output ios/screenshots/6.9-framed \
        --captions ios/AppStore/captions.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CANVAS = (1320, 2868)
# Core/Theme/DS/DSTokens.swift, dark appearance.
BACKGROUND = (0, 0, 0)            # DSPalette.background
TEXT = (245, 245, 247)            # DSPalette.text
EDGE = (44, 44, 46)               # DSPalette.fill2, keeps a black capture off a black page

HEADLINE_TOP = 190
HEADLINE_SIZE = 104
HEADLINE_LINE_GAP = 18
SIDE_MARGIN = 96
SHOT_TOP = 520
SHOT_BOTTOM_MARGIN = 0
CORNER_RADIUS = 70
EDGE_WIDTH = 4

# SF Pro ships with macOS (the CI runner). Locally fall back to a free sans.
FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/SFNSDisplay.ttf",
    "/Library/Fonts/SF-Pro-Display-Semibold.otf",
    "/usr/share/fonts/inter/InterVariable.ttf",
    "/usr/share/fonts/noto/NotoSans-SemiBold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-SemiBold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if not Path(path).exists():
            continue
        font = ImageFont.truetype(path, size)
        # SFNS.ttf and Inter are variable fonts: pick a semibold weight.
        try:
            names = [n.decode() if isinstance(n, bytes) else n for n in font.get_variation_names()]
            for wanted in ("Semibold", "SemiBold", "Bold"):
                if wanted in names:
                    font.set_variation_by_name(wanted)
                    break
        except (OSError, AttributeError):
            pass
        return font
    sys.exit("No usable font found; install Noto Sans or run on macOS.")


def wrap(text: str, font: ImageFont.FreeTypeFont, width: int, draw: ImageDraw.ImageDraw) -> list[str]:
    lines: list[str] = []
    current = ""
    for word in text.split():
        candidate = f"{current} {word}".strip()
        if draw.textlength(candidate, font=font) <= width or not current:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def frame(raw: Path, headline: str, out: Path, font: ImageFont.FreeTypeFont) -> None:
    canvas = Image.new("RGB", CANVAS, BACKGROUND)
    draw = ImageDraw.Draw(canvas)

    y = HEADLINE_TOP
    for line in wrap(headline, font, CANVAS[0] - 2 * SIDE_MARGIN, draw):
        left, top, right, bottom = draw.textbbox((0, 0), line, font=font)
        x = (CANVAS[0] - (right - left)) / 2 - left
        draw.text((x, y), line, font=font, fill=TEXT)
        y += HEADLINE_SIZE + HEADLINE_LINE_GAP

    shot = Image.open(raw).convert("RGB")
    available_h = CANVAS[1] - SHOT_TOP - SHOT_BOTTOM_MARGIN
    scale = available_h / shot.height
    size = (round(shot.width * scale), available_h)
    shot = shot.resize(size, Image.Resampling.LANCZOS)

    x = (CANVAS[0] - size[0]) // 2
    # Only the top corners show; the capture runs off the bottom edge.
    box = (x, SHOT_TOP, x + size[0], SHOT_TOP + size[1] + CORNER_RADIUS)
    edge_box = (box[0] - EDGE_WIDTH, box[1] - EDGE_WIDTH, box[2] + EDGE_WIDTH, box[3])
    draw.rounded_rectangle(edge_box, radius=CORNER_RADIUS + EDGE_WIDTH, fill=EDGE)

    mask = Image.new("L", (size[0], size[1] + CORNER_RADIUS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size[0] - 1, size[1] + CORNER_RADIUS - 1), radius=CORNER_RADIUS, fill=255
    )
    mask = mask.crop((0, 0, size[0], size[1]))
    canvas.paste(shot, (x, SHOT_TOP), mask)

    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "PNG", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--input", required=True, type=Path, help="directory of raw PNG captures")
    parser.add_argument("--output", required=True, type=Path, help="directory for framed PNGs")
    parser.add_argument("--captions", required=True, type=Path, help="JSON of file stem to headline")
    args = parser.parse_args()

    captions: dict[str, str] = json.loads(args.captions.read_text(encoding="utf-8"))
    raws = sorted(args.input.glob("*.png"))
    if not raws:
        print(f"No PNG captures in {args.input}", file=sys.stderr)
        return 1

    font = load_font(HEADLINE_SIZE)
    framed = 0
    for raw in raws:
        headline = captions.get(raw.stem)
        if not headline:
            print(f"skip {raw.name}: no headline")
            continue
        frame(raw, headline, args.output / raw.name, font)
        framed += 1
        print(f"framed {raw.name}: {headline}")

    if framed == 0:
        print("No captures matched a headline", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
