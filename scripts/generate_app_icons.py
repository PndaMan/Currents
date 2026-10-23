"""Draw the app icons from the fish mark in design/brand/currents-fish.svg.

Every icon set gets the three appearances iOS asks for:
  light   the theme-coloured fish on a plain white ground (must be opaque)
  dark    the same fish on a transparent ground; iOS draws its dark backdrop
  tinted  a light grey fish on a transparent ground; iOS applies the tint
It also writes the watch icon, the Logo image set (the bare mark), and the
logo and favicons the README and the docs pages use. Needs rsvg-convert and
Pillow.

    python3 scripts/generate_app_icons.py
"""
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "design/brand/currents-fish.svg"
ASSETS = ROOT / "ios/Currents/Resources/Assets.xcassets"
WATCH = ROOT / "ios/CurrentsWatch/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
DOCS = ROOT / "docs/assets"

SIZE = 1024
MARK = 0.60  # share of the icon the mark's longer side spans
WHITE = (255, 255, 255)
TINT_GREY = (236, 236, 236)

# (fish on white, fish on dark) per theme. The light ones are a step deeper
# where the dark colour would wash out on white.
THEMES = {
    "Ocean": ((10, 132, 255), (47, 164, 245)),
    "Green": ((40, 178, 88), (79, 217, 127)),
    "Teal": ((22, 172, 168), (56, 214, 206)),
    "Purple": ((160, 82, 230), (184, 115, 242)),
    "Rose": ((236, 72, 145), (244, 120, 178)),
    "Ember": ((226, 50, 44), (240, 72, 64)),
    "Sunset": ((242, 128, 20), (248, 150, 52)),
    "Gold": ((222, 166, 18), (242, 204, 77)),
}


def mark_mask(px: int) -> Image.Image:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "mark.png"
        subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), str(SVG), "-o", str(out)], check=True)
        mask = Image.open(out).convert("RGBA").split()[3]
        return mask.crop(mask.getbbox())


def centred(mask: Image.Image, size: int) -> Image.Image:
    full = Image.new("L", (size, size), 0)
    full.paste(mask, ((size - mask.width) // 2, (size - mask.height) // 2))
    return full


def on_white(colour: tuple, mask: Image.Image) -> Image.Image:
    return Image.composite(Image.new("RGB", (SIZE, SIZE), colour), Image.new("RGB", (SIZE, SIZE), WHITE), mask)


def on_clear(colour: tuple, mask: Image.Image) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), colour + (0,))
    img.putalpha(mask)
    return img


def write_set(folder: Path, stem: str, light: tuple, dark: tuple, mask: Image.Image) -> None:
    files = {"": f"{stem}.png", "dark": f"{stem}-dark.png", "tinted": f"{stem}-tinted.png"}
    on_white(light, mask).save(folder / files[""])
    on_clear(dark, mask).save(folder / files["dark"])
    on_clear(TINT_GREY, mask).save(folder / files["tinted"])
    images = []
    for appearance, name in files.items():
        entry = {"filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry = {"appearances": [{"appearance": "luminosity", "value": appearance}], **entry}
        images.append(entry)
    (folder / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def rounded(img: Image.Image, px: int) -> Image.Image:
    """The icon as the home screen shows it: scaled, corners cut, transparent."""
    out = img.resize((px, px), Image.LANCZOS).convert("RGBA")
    corners = Image.new("L", (px * 4, px * 4), 0)
    ImageDraw.Draw(corners).rounded_rectangle([0, 0, px * 4 - 1, px * 4 - 1], radius=px * 4 * 0.225, fill=255)
    out.putalpha(corners.resize((px, px), Image.LANCZOS))
    return out


def bare_mark(colour: tuple, px: int) -> Image.Image:
    mask = mark_mask(round(px * 0.96))
    img = Image.new("RGBA", (px, px), colour + (0,))
    img.putalpha(centred(mask, px))
    return img


def main() -> None:
    mask = centred(mark_mask(round(SIZE * MARK)), SIZE)
    for name, (light, dark) in THEMES.items():
        old = ASSETS / f"AppIcon-{name}.appiconset/AppIcon-{name}-1024.png"
        write_set(old.parent, f"AppIcon-{name}-1024", light, dark, mask)
    write_set(ASSETS / "AppIcon.appiconset", "icon-1024", *THEMES["Ocean"], mask)
    on_white(THEMES["Ocean"][0], mask).save(WATCH)

    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        bare_mark(THEMES["Ocean"][0], 256 * scale).save(ASSETS / f"Logo.imageset/Logo{suffix}.png")
    icon = on_white(THEMES["Ocean"][0], mask)
    bare_mark(THEMES["Ocean"][0], 512).save(DOCS / "logo.png")
    rounded(icon, 180).save(DOCS / "apple-touch-icon.png")
    bare_mark(THEMES["Ocean"][0], 64).save(DOCS / "favicon.png")


if __name__ == "__main__":
    main()
