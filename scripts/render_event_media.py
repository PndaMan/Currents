# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10.4"]
# ///
"""Render App Store in-app event media from raw screenshot captures.

Each event folder under ios/AppStore/events holds an event.json that names
the captures to use and the text to draw. Two images come out per event, at
Apple's minimum sizes for the two placements:

    event-card.png      1920x1080  landscape, shown on the product page and
                                   in search results and Today tabs
    event-details.png   1080x1920  portrait, the full-screen page a tap opens

Both use the app's black background and system font, like the framed
screenshots, so the event looks like the rest of the listing.

    uv run scripts/render_event_media.py \
        --input ios/screenshots/6.9 \
        --events ios/AppStore/events \
        --output ios/screenshots/events
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Core/Theme/DS/DSTokens.swift, dark appearance (same as frame_screenshots.py).
BACKGROUND = (0, 0, 0)
TEXT = (245, 245, 247)
TEXT2 = (174, 174, 178)
EDGE = (44, 44, 46)
CORNER_RADIUS = 70
EDGE_WIDTH = 4

CARD = (1920, 1080)
DETAILS = (1080, 1920)

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/SFNSDisplay.ttf",
    "/Library/Fonts/SF-Pro-Display-Semibold.otf",
    "/usr/share/fonts/inter/InterVariable.ttf",
    "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
    "/usr/share/fonts/noto/NotoSans-SemiBold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-SemiBold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]
REGULAR_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/usr/share/fonts/inter/InterVariable.ttf",
    "/usr/share/fonts/opentype/inter/Inter-Medium.otf",
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def load_font(size: int, candidates: list[str], weight: tuple[str, ...]) -> ImageFont.FreeTypeFont:
    for path in candidates:
        if not Path(path).exists():
            continue
        font = ImageFont.truetype(path, size)
        try:
            names = [n.decode() if isinstance(n, bytes) else n for n in font.get_variation_names()]
            for wanted in weight:
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


def draw_block(draw: ImageDraw.ImageDraw, x: int, y: int, width: int, headline: str, subline: str | None,
               head_font: ImageFont.FreeTypeFont, sub_font: ImageFont.FreeTypeFont, head_size: int,
               sub_size: int, align: str) -> int:
    """Draw headline and sub-line; return the y just below them."""
    for line in wrap(headline, head_font, width, draw):
        left, _, right, _ = draw.textbbox((0, 0), line, font=head_font)
        lx = x + (width - (right - left)) / 2 - left if align == "center" else x - left
        draw.text((lx, y), line, font=head_font, fill=TEXT)
        y += round(head_size * 1.15)
    if subline:
        y += round(sub_size * 0.6)
        for line in wrap(subline, sub_font, width, draw):
            left, _, right, _ = draw.textbbox((0, 0), line, font=sub_font)
            lx = x + (width - (right - left)) / 2 - left if align == "center" else x - left
            draw.text((lx, y), line, font=sub_font, fill=TEXT2)
            y += round(sub_size * 1.3)
    return y


def paste_phone(canvas: Image.Image, shot: Image.Image, x: int, y: int, height: int) -> int:
    """Scale a capture to `height`, round its top corners, bleed it off the
    bottom of the canvas. Returns the drawn width."""
    draw = ImageDraw.Draw(canvas)
    scale = height / shot.height
    size = (round(shot.width * scale), height)
    shot = shot.resize(size, Image.Resampling.LANCZOS)
    radius = round(CORNER_RADIUS * scale * 1.6)
    box = (x, y, x + size[0], y + size[1] + radius)
    edge_box = (box[0] - EDGE_WIDTH, box[1] - EDGE_WIDTH, box[2] + EDGE_WIDTH, box[3])
    draw.rounded_rectangle(edge_box, radius=radius + EDGE_WIDTH, fill=EDGE)
    mask = Image.new("L", (size[0], size[1] + radius), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] + radius - 1), radius=radius, fill=255)
    canvas.paste(shot, (x, y), mask.crop((0, 0, size[0], size[1])))
    return size[0]


def render_card(shots: list[Image.Image], headline: str, subline: str | None, out: Path) -> None:
    canvas = Image.new("RGB", CARD, BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    margin = 110
    head = load_font(96, FONT_CANDIDATES, ("Semibold", "SemiBold", "Bold"))
    sub = load_font(44, REGULAR_CANDIDATES, ("Medium", "Regular"))

    # One or two phones on the right, bleeding off the bottom edge.
    phone_h = 940
    top = CARD[1] - phone_h + 60
    gap = 48
    width = round(shots[0].width * phone_h / shots[0].height)
    total = width * len(shots[:2]) + gap * (len(shots[:2]) - 1)
    phones_x = CARD[0] - margin - total
    x = phones_x
    for shot in shots[:2]:
        x += paste_phone(canvas, shot, x, top, phone_h) + gap

    # Text fills whatever is left of the phones, vertically centred.
    text_width = phones_x - margin - 90
    probe = Image.new("RGB", (1, 1))
    end = draw_block(ImageDraw.Draw(probe), 0, 0, text_width, headline, subline, head, sub, 96, 44, "left")
    y0 = max(margin, (CARD[1] - end) // 2)
    draw_block(draw, margin, y0, text_width, headline, subline, head, sub, 96, 44, "left")
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "PNG", optimize=True)


def render_details(shots: list[Image.Image], headline: str, subline: str | None, out: Path) -> None:
    canvas = Image.new("RGB", DETAILS, BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    margin = 90
    head = load_font(92, FONT_CANDIDATES, ("Semibold", "SemiBold", "Bold"))
    sub = load_font(44, REGULAR_CANDIDATES, ("Medium", "Regular"))
    end = draw_block(draw, margin, 150, DETAILS[0] - 2 * margin, headline, subline, head, sub, 92, 44, "center")
    top = end + 90
    phone_h = DETAILS[1] - top + 80
    width = round(shots[0].width * phone_h / shots[0].height)
    paste_phone(canvas, shots[0], (DETAILS[0] - width) // 2, top, phone_h)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "PNG", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--input", required=True, type=Path, help="directory of raw PNG captures")
    parser.add_argument("--events", required=True, type=Path, help="directory of event folders")
    parser.add_argument("--output", required=True, type=Path, help="directory for rendered media")
    args = parser.parse_args()

    rendered = 0
    for folder in sorted(p for p in args.events.iterdir() if p.is_dir()):
        spec_path = folder / "event.json"
        if not spec_path.exists():
            continue
        spec = json.loads(spec_path.read_text(encoding="utf-8"))
        media = spec.get("media", {})
        shots = []
        for stem in media.get("captures", []):
            path = args.input / f"{stem}.png"
            if not path.exists():
                print(f"skip {folder.name}: no capture {path.name} in {args.input}", file=sys.stderr)
                break
            shots.append(Image.open(path).convert("RGB"))
        else:
            if not shots:
                print(f"skip {folder.name}: event.json lists no captures")
                continue
            headline = media.get("headline") or (folder / "name.txt").read_text(encoding="utf-8").strip()
            subline = media.get("subline") or (folder / "short_description.txt").read_text(encoding="utf-8").strip()
            render_card(shots, headline, subline, args.output / folder.name / "event-card.png")
            render_details(shots, headline, subline, args.output / folder.name / "event-details.png")
            rendered += 1
            print(f"rendered {folder.name}: {headline}")

    if rendered == 0:
        print("No events rendered", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
