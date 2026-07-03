#!/usr/bin/env python3
"""
Generate alternate app-icon sets from the themed Logo art.

The Info.plist previously declared alternate icons (AppIcon-Green, -Purple,
-Gold, -Ocean) that had no matching images in the bundle, which fails App
Store validation (ITMS-90032). This composites each themed logo mark onto a
light gradient background — matching the primary icon — and writes proper
`.appiconset`s the asset catalog can compile.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
ASSETS = REPO / "ios/Currents/Resources/Assets.xcassets"
SIZE = 1024

# (icon set name, logo imageset, background top color, background bottom color)
VARIANTS = [
    ("AppIcon-Ocean", "Logo", (0.86, 0.93, 0.99), (0.72, 0.85, 0.97)),
    ("AppIcon-Green", "LogoGreen", (0.88, 0.96, 0.90), (0.74, 0.90, 0.78)),
    ("AppIcon-Purple", "LogoPurple", (0.92, 0.89, 0.98), (0.80, 0.74, 0.94)),
    ("AppIcon-Gold", "LogoGold", (0.98, 0.95, 0.85), (0.95, 0.87, 0.66)),
]


def logo_png(imageset: str) -> Path:
    d = ASSETS / f"{imageset}.imageset"
    return next(p for p in d.iterdir() if p.suffix == ".png")


def gradient(top: tuple, bottom: tuple) -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        r = int((top[0] * (1 - t) + bottom[0] * t) * 255)
        g = int((top[1] * (1 - t) + bottom[1] * t) * 255)
        b = int((top[2] * (1 - t) + bottom[2] * t) * 255)
        for x in range(SIZE):
            px[x, y] = (r, g, b)
    return img


def build(name: str, imageset: str, top: tuple, bottom: tuple) -> None:
    bg = gradient(top, bottom)
    logo = Image.open(logo_png(imageset)).convert("RGBA")

    # Scale the mark to ~82% of the icon and center it.
    target = int(SIZE * 0.82)
    logo = logo.resize((target, target), Image.LANCZOS)
    offset = (SIZE - target) // 2
    bg.paste(logo, (offset, offset), logo)

    out_dir = ASSETS / f"{name}.appiconset"
    out_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{name}-1024.png"
    bg.save(out_dir / filename, "PNG")

    contents = {
        "images": [
            {
                "filename": filename,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (out_dir / "Contents.json").write_text(json.dumps(contents, indent=2))
    print(f"  wrote {out_dir.relative_to(REPO)}")


def main() -> None:
    print("Generating alternate app icons…")
    for name, imageset, top, bottom in VARIANTS:
        build(name, imageset, top, bottom)
    print("Done.")


if __name__ == "__main__":
    main()
