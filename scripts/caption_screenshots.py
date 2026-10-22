#!/usr/bin/env python3
"""Add App Store caption headers to raw simulator screenshots.

The screenshots workflow captures bare 1320x2868 simulator frames. This script
turns each one into a store-ready image: a short headline (and optional
sub-line) on a dark gradient, with the capture itself scaled down, given
rounded "device" corners and bled off the bottom edge, the layout every
top-ranked fishing app uses, and the one Apple's own guidelines favour.

Output images keep the input dimensions exactly, so a 6.9" capture stays a
valid 6.9" upload. Images the captions file doesn't mention (e.g. the Apple
Watch capture, which has no room for a header) are copied through untouched.

Usage:
    python3 scripts/caption_screenshots.py \
        --captions docs/app-store/screenshots/captions.json \
        --input ios/screenshots/6.9 \
        --output ios/screenshots/captioned

Requires Pillow (`pip3 install pillow`). Fonts: the first match from the
--font / --font-regular lists wins, so it works unmodified on macOS CI
runners (Helvetica Neue) and on Linux (Inter / DejaVu).
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - import guard for a clearer error
    sys.exit("Pillow is required: pip3 install pillow")


# Candidate font files, tried in order. Tuples are (path, face index) for
# .ttc collections. macOS entries come first because CI runs on macos-15.
BOLD_FONTS = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 1),      # Helvetica Neue Bold
    ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0),
    ("/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf", 0),
    ("/usr/share/fonts/opentype/inter/Inter-Bold.otf", 0),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 0),
]
REGULAR_FONTS = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 0),      # Helvetica Neue Regular
    ("/System/Library/Fonts/Supplemental/Arial.ttf", 0),
    ("/usr/share/fonts/opentype/inter/Inter-Medium.otf", 0),
    ("/usr/share/fonts/opentype/inter/Inter-Regular.otf", 0),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 0),
]


@dataclass(frozen=True)
class Style:
    """Layout constants, expressed for a 1320x2868 canvas and scaled from it."""

    width: int
    height: int
    top_pad: int = 150           # gap above the headline
    headline_size: int = 104
    subline_size: int = 50
    line_gap: int = 18           # between wrapped headline lines
    block_gap: int = 34          # between headline and sub-line
    shot_gap: int = 110          # between text block and the screenshot
    shot_scale: float = 0.86     # screenshot width as a fraction of canvas
    corner_radius: int = 150     # device corner radius at full scale
    bezel: int = 14              # dark ring around the screenshot
    side_margin: int = 96        # min horizontal text margin
    bg_top: tuple[int, int, int] = (7, 17, 28)
    bg_bottom: tuple[int, int, int] = (11, 31, 51)
    headline_rgb: tuple[int, int, int] = (255, 255, 255)
    subline_rgb: tuple[int, int, int] = (171, 190, 209)
    bezel_rgb: tuple[int, int, int] = (28, 32, 38)

    @classmethod
    def for_size(cls, width: int, height: int) -> "Style":
        # Everything is designed for the 6.9" slot; scale proportionally so a
        # 6.5" (1284x2778) or 6.1" capture gets the same look.
        f = width / 1320
        return cls(
            width=width,
            height=height,
            top_pad=round(150 * f),
            headline_size=round(104 * f),
            subline_size=round(50 * f),
            line_gap=round(18 * f),
            block_gap=round(34 * f),
            shot_gap=round(110 * f),
            corner_radius=round(150 * f),
            bezel=round(14 * f),
            side_margin=round(96 * f),
        )


def load_font(candidates, size: int, override: str | None) -> ImageFont.FreeTypeFont:
    paths = [(override, 0)] if override else []
    paths += candidates
    for path, index in paths:
        if path and Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size, index=index)
            except OSError:
                continue
    print("warning: no TrueType font found, falling back to Pillow's bitmap font", file=sys.stderr)
    return ImageFont.load_default()


def wrap(text: str, font: ImageFont.FreeTypeFont, max_width: int, draw: ImageDraw.ImageDraw) -> list[str]:
    """Greedy word wrap. Explicit newlines in the caption are respected."""
    lines: list[str] = []
    for paragraph in text.split("\n"):
        words = paragraph.split()
        if not words:
            lines.append("")
            continue
        current = words[0]
        for word in words[1:]:
            candidate = f"{current} {word}"
            if draw.textlength(candidate, font=font) <= max_width:
                current = candidate
            else:
                lines.append(current)
                current = word
        lines.append(current)
    return lines


def gradient(width: int, height: int, top: tuple, bottom: tuple) -> Image.Image:
    """Vertical linear gradient, built from a 1px-wide column for speed."""
    column = Image.new("RGB", (1, height))
    px = column.load()
    for y in range(height):
        t = y / max(height - 1, 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return column.resize((width, height))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (size[0] - 1, size[1] - 1)], radius=radius, fill=255)
    return mask


def caption_image(src: Path, dst: Path, headline: str, subline: str | None,
                  bold_override: str | None, regular_override: str | None) -> None:
    shot = Image.open(src).convert("RGB")
    style = Style.for_size(*shot.size)
    canvas = gradient(style.width, style.height, style.bg_top, style.bg_bottom)
    draw = ImageDraw.Draw(canvas)

    headline_font = load_font(BOLD_FONTS, style.headline_size, bold_override)
    subline_font = load_font(REGULAR_FONTS, style.subline_size, regular_override)
    text_width = style.width - 2 * style.side_margin

    # Headline block, centred.
    y = style.top_pad
    for line in wrap(headline, headline_font, text_width, draw):
        w = draw.textlength(line, font=headline_font)
        draw.text(((style.width - w) / 2, y), line, font=headline_font, fill=style.headline_rgb)
        y += style.headline_size + style.line_gap
    y -= style.line_gap

    if subline:
        y += style.block_gap
        for line in wrap(subline, subline_font, text_width, draw):
            w = draw.textlength(line, font=subline_font)
            draw.text(((style.width - w) / 2, y), line, font=subline_font, fill=style.subline_rgb)
            y += round(style.subline_size * 1.28)

    # Screenshot: scaled, rounded, bezelled, bleeding off the bottom edge.
    shot_w = round(style.width * style.shot_scale)
    shot_h = round(shot.height * shot_w / shot.width)
    shot_small = shot.resize((shot_w, shot_h), Image.LANCZOS)
    radius = round(style.corner_radius * style.shot_scale)
    shot_x = (style.width - shot_w) // 2
    shot_y = y + style.shot_gap

    bezel_box = [(shot_x - style.bezel, shot_y - style.bezel),
                 (shot_x + shot_w + style.bezel, shot_y + shot_h + style.bezel)]
    draw.rounded_rectangle(bezel_box, radius=radius + style.bezel, fill=style.bezel_rgb)
    canvas.paste(shot_small, (shot_x, shot_y), rounded_mask(shot_small.size, radius))

    dst.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dst, "PNG", optimize=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--captions", required=True, type=Path, help="JSON file mapping filenames to captions")
    parser.add_argument("--input", required=True, type=Path, help="directory of raw screenshots")
    parser.add_argument("--output", required=True, type=Path, help="directory for captioned output")
    parser.add_argument("--font", help="override: path to a bold TrueType/OpenType font")
    parser.add_argument("--font-regular", help="override: path to a regular-weight font")
    parser.add_argument("--only", nargs="*", help="only process these filenames (for previews)")
    args = parser.parse_args(argv)

    spec = json.loads(args.captions.read_text(encoding="utf-8"))
    captions: dict[str, dict] = spec["screenshots"] if "screenshots" in spec else spec
    args.output.mkdir(parents=True, exist_ok=True)

    processed = 0
    for src in sorted(args.input.glob("*.png")):
        if args.only and src.name not in args.only:
            continue
        dst = args.output / src.name
        entry = captions.get(src.name)
        if not entry:
            shutil.copyfile(src, dst)
            print(f"copied    {src.name} (no caption configured)")
            continue
        caption_image(src, dst, entry["headline"], entry.get("subline"), args.font, args.font_regular)
        print(f"captioned {src.name}: {entry['headline']!r}")
        processed += 1

    missing = [name for name in captions if not (args.input / name).exists()]
    for name in missing:
        print(f"warning: caption configured for {name} but no such screenshot in {args.input}", file=sys.stderr)
    print(f"done: {processed} captioned -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
