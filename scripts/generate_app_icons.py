"""Draw the app icons from the fish mark in design/brand/currents-fish.svg.

One icon per colour theme, on the dark background with a glow in the theme's
hue, plus the dark and tinted appearances of the primary icon, the watch
icon, the Logo image set (the bare mark), and the logo and favicon the README
and the docs pages use. Needs rsvg-convert and Pillow.

    python3 scripts/generate_app_icons.py
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "design/brand/currents-fish.svg"
ASSETS = ROOT / "ios/Currents/Resources/Assets.xcassets"
WATCH = ROOT / "ios/CurrentsWatch/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
DOCS = ROOT / "docs/assets"

SIZE = 1024
MARK = 0.56  # share of the icon width the mark spans
EDGE_TOP = (23, 25, 30)
EDGE_BOTTOM = (12, 15, 18)

# (mark colour, glow colour) per theme, taken from the shipped icons.
THEMES = {
    "Ocean": ((47, 164, 245), (26, 44, 58)),
    "Green": ((79, 217, 127), (30, 50, 43)),
    "Teal": ((56, 214, 206), (27, 50, 53)),
    "Purple": ((184, 115, 242), (44, 37, 57)),
    "Rose": ((244, 120, 178), (52, 38, 49)),
    "Ember": ((240, 72, 64), (51, 31, 34)),
    "Sunset": ((248, 150, 52), (52, 42, 33)),
    "Gold": ((242, 204, 77), (51, 49, 36)),
}
TINTED = ((235, 235, 235), (43, 45, 49))


def mark_mask(px: int) -> Image.Image:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "mark.png"
        subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), str(SVG), "-o", str(out)], check=True)
        return Image.open(out).convert("RGBA").split()[3]


def background(glow: tuple) -> Image.Image:
    bg = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(bg)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        draw.line([(0, y), (SIZE, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(EDGE_TOP, EDGE_BOTTOM)))
    halo = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(halo).ellipse([SIZE * 0.12, SIZE * 0.12, SIZE * 0.88, SIZE * 0.88], fill=255)
    halo = halo.filter(ImageFilter.GaussianBlur(SIZE * 0.16))
    return Image.composite(Image.new("RGB", (SIZE, SIZE), glow), bg, halo)


def icon(mark: tuple, glow: tuple, mask: Image.Image) -> Image.Image:
    img = background(glow)
    box = mask.getbbox()
    cropped = mask.crop(box)
    x = (SIZE - cropped.width) // 2
    y = (SIZE - cropped.height) // 2
    full = Image.new("L", (SIZE, SIZE), 0)
    full.paste(cropped, (x, y))
    return Image.composite(Image.new("RGB", (SIZE, SIZE), mark), img, full)


def rounded(img: Image.Image, px: int) -> Image.Image:
    """The icon as the home screen shows it: scaled, corners cut, transparent."""
    out = img.resize((px, px), Image.LANCZOS).convert("RGBA")
    corners = Image.new("L", (px * 4, px * 4), 0)
    ImageDraw.Draw(corners).rounded_rectangle([0, 0, px * 4 - 1, px * 4 - 1], radius=px * 4 * 0.225, fill=255)
    out.putalpha(corners.resize((px, px), Image.LANCZOS))
    return out


def bare_mark(colour: tuple, px: int) -> Image.Image:
    mask = mark_mask(px)
    mark = Image.new("RGBA", (px, px), colour + (0,))
    mark.putalpha(mask)
    return mark


def main() -> None:
    mask = mark_mask(round(SIZE * MARK * 1.06))
    for name, (mark, glow) in THEMES.items():
        img = icon(mark, glow, mask)
        img.save(ASSETS / f"AppIcon-{name}.appiconset/AppIcon-{name}-1024.png")
        if name == "Ocean":
            img.save(ASSETS / "AppIcon.appiconset/icon-1024.png")
            img.save(ASSETS / "AppIcon.appiconset/icon-1024-dark.png")
            img.save(WATCH)
    icon(*TINTED, mask).save(ASSETS / "AppIcon.appiconset/icon-1024-tinted.png")

    ocean = icon(*THEMES["Ocean"], mask)
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        bare_mark(THEMES["Ocean"][0], 256 * scale).save(ASSETS / f"Logo.imageset/Logo{suffix}.png")
    rounded(ocean, 512).save(DOCS / "logo.png")
    rounded(ocean, 180).save(DOCS / "apple-touch-icon.png")
    rounded(ocean, 64).save(DOCS / "favicon.png")


if __name__ == "__main__":
    main()
