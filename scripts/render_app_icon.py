#!/usr/bin/env python3
"""
Render every Currents icon asset from one vector definition of the mark.

The mark is a diagonal fish drawn as a single monoline outline, nose pointing
up-right at 45°, with a solid dot for the eye. The outline is white; the eye is
the one accent and carries the theme colour. The geometry lives in this file as
normalised (0..1) control points so the same curves drive:

  * the SVG that becomes the App Store / Home Screen icon PNGs,
  * the SwiftUI `Shape`s that draw the logo inside the app, widgets and watch
    (`--swift` regenerates ios/Shared/CurrentsMark.swift).

Outputs (all regenerated in place):

  ios/Currents/Resources/Assets.xcassets/AppIcon.appiconset/       default, dark, tinted
  ios/Currents/Resources/Assets.xcassets/AppIcon-<Theme>.appiconset/ one per theme, each with
                                                                     default, dark, tinted
  ios/Currents/Resources/Assets.xcassets/Logo*.imageset/           transparent mark, 1x/2x/3x
  ios/CurrentsWatch/Assets.xcassets/AppIcon.appiconset/            circular-safe watch icon
  docs/assets/logo.png                                             README logo (rounded, transparent)
  design/icon/currents-icon.svg                                    editable source
  design/icon/currents-mark.svg                                    the mark alone, transparent
  design/icon/layers/{background,fish,eye}.svg                     Icon Composer layers
  design/icon/preview.png                                          contact sheet

Deps: pip install cairosvg pillow numpy
Usage:
    python scripts/render_app_icon.py            # render everything
    python scripts/render_app_icon.py --swift    # regenerate ios/Shared/CurrentsMark.swift
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ASSETS = REPO / "ios/Currents/Resources/Assets.xcassets"
WATCH_ICON = REPO / "ios/CurrentsWatch/Assets.xcassets/AppIcon.appiconset"
DESIGN = REPO / "design/icon"
DOCS_LOGO = REPO / "docs/assets/logo.png"
SWIFT_OUT = REPO / "ios/Shared/CurrentsMark.swift"

SIZE = 1024

# --------------------------------------------------------------------------
# Colour
# --------------------------------------------------------------------------

# Dark charcoal, sampled from Apple's iOS 26 dark-appearance system icons
# (Clock / Calendar): a quiet top-to-bottom falloff, never pure black.
BG_DEFAULT = ("#3A3A3C", "#1F1F21")
BG_DARK = ("#2C2C2E", "#161618")
BG_TINTED = ("#1C1C1E", "#1C1C1E")   # tinted icons sit on a flat near-black
BG_WATCH = ("#48484A", "#2A2A2C")     # HIG: lighten black on watchOS

LINE = "#F5F5F7"
LINE_TINTED = "#FFFFFF"
EYE_TINTED = "#9A9A9E"                # greys keep the two-tone in tinted mode

# Accent per theme = the light stop of ThemeOption.gradient in LiquidGlass.swift,
# so the icon's eye and the in-app wordmark gradient agree.
THEMES = {
    "ocean":    "#26D1FA",
    "forest":   "#4DD980",
    "ember":    "#F26640",
    "sunset":   "#FABF40",
    "amethyst": "#B873F2",
    "teal":     "#40D9D9",
    "rose":     "#F280B3",
    "gold":     "#F2CC4D",
}

# Alternate icon set name -> theme (matches AppIconOption + project.yml)
ALT_ICONS = {
    "AppIcon-Ocean": "ocean",
    "AppIcon-Green": "forest",
    "AppIcon-Teal": "teal",
    "AppIcon-Purple": "amethyst",
    "AppIcon-Rose": "rose",
    "AppIcon-Ember": "ember",
    "AppIcon-Sunset": "sunset",
    "AppIcon-Gold": "gold",
}

# Transparent in-app logo imagesets -> theme of the eye
LOGO_SETS = {
    "Logo": "ocean",
    "LogoGreen": "forest",
    "LogoPurple": "amethyst",
    "LogoGold": "gold",
}

# --------------------------------------------------------------------------
# Geometry (unit square, fish drawn horizontally facing right, then rotated)
# --------------------------------------------------------------------------

# Closed monoline outline: a long teardrop body that tapers to a narrow
# peduncle, and a wide fan tail with a shallow concave trailing edge.
OUTLINE = [
    ("M", (0.92, 0.50)),                                    # nose
    ("C", (0.88, 0.36), (0.74, 0.29), (0.60, 0.29)),        # over the head and back
    ("C", (0.47, 0.29), (0.38, 0.38), (0.31, 0.46)),        # taper to the peduncle
    ("C", (0.25, 0.42), (0.17, 0.34), (0.10, 0.30)),        # upper tail lobe
    ("C", (0.16, 0.41), (0.16, 0.59), (0.10, 0.70)),        # concave trailing edge
    ("C", (0.17, 0.66), (0.25, 0.58), (0.31, 0.54)),        # lower lobe back in
    ("C", (0.38, 0.62), (0.47, 0.71), (0.60, 0.71)),        # belly
    ("C", (0.74, 0.71), (0.88, 0.64), (0.92, 0.50)),        # chin to nose
    ("Z",),
]
EYE = (0.78, 0.44, 0.040)                 # cx, cy, r (pre-rotation, unit coords)
LINE_WIDTH = 0.048                        # stroke width as a fraction of the icon

TILT_DEG = -45.0                          # nose up-right
ICON_SCALE = 0.88                         # mark size as a fraction of the icon
WATCH_SCALE = 0.72                        # stays inside the circular mask
LOGO_SCALE = 0.96                         # transparent imagesets: fill the box


def transform(scale=1.0, cx=0.5, cy=0.5, rot_deg=TILT_DEG):
    r = math.radians(rot_deg)
    cos, sin = math.cos(r), math.sin(r)

    def t(p):
        x, y = (p[0] - 0.5) * scale, (p[1] - 0.5) * scale
        return (x * cos - y * sin + cx, x * sin + y * cos + cy)
    return t


def to_svg_d(path, t):
    parts = []
    for seg in path:
        cmd, *ps = seg
        parts.append(cmd + " ".join(f"{x:.4f},{y:.4f}" for x, y in map(t, ps)))
    return " ".join(parts)


# --------------------------------------------------------------------------
# SVG
# --------------------------------------------------------------------------

def svg_document(scale, bg, line, eye, *, layers=None):
    """Full icon SVG. `bg` is (top, bottom) or None for transparent.

    `layers` may be a subset of {"background", "fish", "eye"} to emit a single
    Icon Composer layer.
    """
    layers = layers or {"background", "fish", "eye"}
    t = transform(scale)
    body = []
    if "background" in layers and bg:
        body.append(
            '<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{bg[0]}"/><stop offset="1" stop-color="{bg[1]}"/>'
            '</linearGradient></defs>'
            '<rect width="1" height="1" fill="url(#bg)"/>'
        )
    if "fish" in layers:
        body.append(f'<path d="{to_svg_d(OUTLINE, t)}" fill="none" stroke="{line}" '
                    f'stroke-width="{LINE_WIDTH * scale / ICON_SCALE:.4f}" stroke-linejoin="round"/>')
    if "eye" in layers:
        ex, ey, er = EYE
        cx, cy = t((ex, ey))
        body.append(f'<circle cx="{cx:.4f}" cy="{cy:.4f}" r="{er * scale:.4f}" fill="{eye}"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1" '
            f'width="{SIZE}" height="{SIZE}">' + "".join(body) + "</svg>")


def render_png(svg_text, out: Path, size=SIZE):
    import cairosvg
    out.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(bytestring=svg_text.encode(), write_to=str(out),
                     output_width=size, output_height=size)


# --------------------------------------------------------------------------
# Asset catalogs
# --------------------------------------------------------------------------

def appiconset_contents(prefix: str, platform: str, variants: bool) -> dict:
    images = [{"filename": f"{prefix}.png", "idiom": "universal",
               "platform": platform, "size": "1024x1024"}]
    if variants:
        for appearance in ("dark", "tinted"):
            images.append({
                "appearances": [{"appearance": "luminosity", "value": appearance}],
                "filename": f"{prefix}-{appearance}.png",
                "idiom": "universal", "platform": platform, "size": "1024x1024",
            })
    return {"images": images, "info": {"author": "xcode", "version": 1}}


def write_json(path: Path, data: dict):
    path.write_text(json.dumps(data, indent=2) + "\n")


def render_icon_set(out_dir: Path, prefix: str, theme: str):
    """Default + dark + tinted 1024 PNGs for one appiconset."""
    accent = THEMES[theme]
    render_png(svg_document(ICON_SCALE, BG_DEFAULT, LINE, accent), out_dir / f"{prefix}.png")
    render_png(svg_document(ICON_SCALE, BG_DARK, LINE, accent), out_dir / f"{prefix}-dark.png")
    render_png(svg_document(ICON_SCALE, BG_TINTED, LINE_TINTED, EYE_TINTED),
               out_dir / f"{prefix}-tinted.png")
    write_json(out_dir / "Contents.json", appiconset_contents(prefix, "ios", True))
    print(f"  wrote {out_dir.relative_to(REPO)}")


def render_logo_set(name: str, theme: str):
    out_dir = ASSETS / f"{name}.imageset"
    svg = svg_document(LOGO_SCALE, None, LINE, THEMES[theme])
    images = []
    for scale, px in ((1, 256), (2, 512), (3, 768)):
        fn = f"{name}.png" if scale == 1 else f"{name}@{scale}x.png"
        render_png(svg, out_dir / fn, px)
        images.append({"filename": fn, "idiom": "universal", "scale": f"{scale}x"})
    write_json(out_dir / "Contents.json",
               {"images": images, "info": {"author": "xcode", "version": 1}})
    print(f"  wrote {out_dir.relative_to(REPO)}")


# --------------------------------------------------------------------------
# README logo + preview sheet
# --------------------------------------------------------------------------

def squircle_mask(size: int, n: float = 5.0):
    """iOS-style continuous-corner mask (superellipse), supersampled."""
    import numpy as np
    from PIL import Image
    ss = 4
    s = size * ss
    y, x = np.mgrid[0:s, 0:s]
    cx = cy = (s - 1) / 2
    a = s / 2
    v = (np.abs((x - cx) / a) ** n + np.abs((y - cy) / a) ** n) <= 1.0
    m = Image.fromarray((v * 255).astype("uint8"))
    return m.resize((size, size), Image.LANCZOS)


def render_docs_logo():
    from PIL import Image
    tmp = DOCS_LOGO.with_suffix(".tmp.png")
    render_png(svg_document(ICON_SCALE, BG_DEFAULT, LINE, THEMES["ocean"]), tmp)
    im = Image.open(tmp).convert("RGBA")
    im.putalpha(squircle_mask(SIZE))
    im.save(DOCS_LOGO)
    tmp.unlink()
    print(f"  wrote {DOCS_LOGO.relative_to(REPO)}")


def render_preview():
    from PIL import Image, ImageDraw
    tile, gap, pad = 160, 28, 40
    themes = list(THEMES)
    rows = [("default", BG_DEFAULT, LINE, None), ("dark", BG_DARK, LINE, None),
            ("tinted", BG_TINTED, LINE_TINTED, EYE_TINTED)]
    W = pad * 2 + 120 + len(themes) * (tile + gap)
    H = pad * 2 + len(rows) * (tile + gap) + 220
    sheet = Image.new("RGB", (W, H), (236, 236, 241))
    d = ImageDraw.Draw(sheet)
    mask = squircle_mask(tile)
    tmp = DESIGN / "_tmp.png"
    for r, (label, bg, line, eye) in enumerate(rows):
        y = pad + r * (tile + gap)
        d.text((pad, y + tile // 2), label, fill=(60, 60, 70), anchor="lm")
        for c, theme in enumerate(themes):
            x = pad + 120 + c * (tile + gap)
            render_png(svg_document(ICON_SCALE, bg, line, eye or THEMES[theme]), tmp, tile)
            sheet.paste(Image.open(tmp).convert("RGB"), (x, y), mask)
            if r == 0:
                d.text((x + tile // 2, y - 14), theme, fill=(60, 60, 70), anchor="mm")
    # size ladder on light and dark
    y = pad + len(rows) * (tile + gap) + 20
    d.text((pad, y + 60), "sizes", fill=(60, 60, 70), anchor="lm")
    render_png(svg_document(ICON_SCALE, BG_DEFAULT, LINE, THEMES["ocean"]), tmp, 256)
    big = Image.open(tmp).convert("RGB")
    x = pad + 120
    for px in (29, 40, 58, 76, 120, 180):
        im = big.resize((px, px), Image.LANCZOS)
        sheet.paste(im, (x, y + 90 - px // 2), squircle_mask(px))
        d.text((x + px // 2, y + 170), f"{px}px", fill=(60, 60, 70), anchor="mm")
        x += px + 34
    dark = Image.new("RGB", (W - x - pad, 200), (28, 28, 30))
    sheet.paste(dark, (x, y))
    # in-app mark: outline in the theme colour, eye in the same colour
    render_png(svg_document(LOGO_SCALE, None, "#1E8CF0", "#1E8CF0"), tmp, 150)
    logo = Image.open(tmp).convert("RGBA")
    sheet.paste(logo, (x + 20, y + 25), logo)
    render_png(svg_document(WATCH_SCALE, BG_WATCH, LINE, THEMES["ocean"]), tmp, 150)
    w = Image.open(tmp).convert("RGB")
    circ = Image.new("L", (150, 150), 0)
    ImageDraw.Draw(circ).ellipse((0, 0, 149, 149), fill=255)
    sheet.paste(w, (x + 200, y + 25), circ)
    tmp.unlink()
    sheet.save(DESIGN / "preview.png")
    print(f"  wrote {(DESIGN / 'preview.png').relative_to(REPO)}")


# --------------------------------------------------------------------------
# SwiftUI export
# --------------------------------------------------------------------------

def swift_code() -> str:
    t = transform(1.0)  # tilt baked in, unit square

    def pt(p):
        x, y = t(p)
        return f"CGPoint(x: w * {x:.4f}, y: h * {y:.4f})"

    lines = ["    func path(in rect: CGRect) -> Path {",
             "        var p = Path()",
             "        let w = rect.width, h = rect.height"]
    for seg in OUTLINE:
        cmd, *ps = seg
        if cmd == "M":
            lines.append(f"        p.move(to: {pt(ps[0])})")
        elif cmd == "C":
            lines.append(f"        p.addCurve(to: {pt(ps[2])},")
            lines.append(f"                   control1: {pt(ps[0])},")
            lines.append(f"                   control2: {pt(ps[1])})")
        else:
            lines.append("        p.closeSubpath()")
    lines.append("        return p")
    lines.append("    }")
    outline = "\n".join(lines)

    ex, ey, er = EYE
    cx, cy = t((ex, ey))
    eye = (f"    func path(in rect: CGRect) -> Path {{\n"
           f"        let w = rect.width, h = rect.height\n"
           f"        return Path(ellipseIn: CGRect(x: w * {cx - er:.4f}, y: h * {cy - er:.4f}, "
           f"width: w * {2 * er:.4f}, height: h * {2 * er:.4f}))\n"
           f"    }}")

    # Stroke width relative to the mark's own bounding square, so a
    # `.frame(width: s, height: s)` of the view gives the icon's proportions.
    stroke = LINE_WIDTH / ICON_SCALE
    return f"""import SwiftUI

// Generated by `python scripts/render_app_icon.py --swift` — do not hand-edit.
// The same control points render the App Store / Home Screen icon PNGs, so the
// in-app logo and the icon are guaranteed to be the same mark.

/// The fish outline, nose up-right at {abs(TILT_DEG):g}°. Stroke it; never fill it.
struct CurrentsFishOutline: Shape {{
{outline}
}}

/// The eye: a solid dot. Fill it.
struct CurrentsFishEye: Shape {{
{eye}
}}

/// The Currents mark: a monoline fish outline in `tint` with a solid eye in
/// `accent` (defaults to `tint`, so the in-app logo is one colour).
///
/// The Home Screen icon is the inverse: white outline, theme-coloured eye.
/// Square; size it with `.frame(width:height:)`.
struct CurrentsMark: View {{
    var tint: Color
    var accent: Color? = nil

    /// Stroke width as a fraction of the view's side.
    static let lineWidth: CGFloat = {stroke:.4f}

    var body: some View {{
        GeometryReader {{ geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {{
                CurrentsFishOutline()
                    .stroke(tint, style: StrokeStyle(lineWidth: side * Self.lineWidth,
                                                     lineJoin: .round))
                CurrentsFishEye()
                    .fill(accent ?? tint)
            }}
            .frame(width: side, height: side)
        }}
        .aspectRatio(1, contentMode: .fit)
    }}
}}
"""


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--swift", action="store_true",
                    help=f"regenerate {SWIFT_OUT.relative_to(REPO)} and exit")
    args = ap.parse_args()
    if args.swift:
        SWIFT_OUT.write_text(swift_code())
        print(f"  wrote {SWIFT_OUT.relative_to(REPO)}")
        return

    print("Rendering Currents icon assets…")
    render_icon_set(ASSETS / "AppIcon.appiconset", "icon-1024", "ocean")
    for name, theme in ALT_ICONS.items():
        render_icon_set(ASSETS / f"{name}.appiconset", f"{name}-1024", theme)
    for name, theme in LOGO_SETS.items():
        render_logo_set(name, theme)

    render_png(svg_document(WATCH_SCALE, BG_WATCH, LINE, THEMES["ocean"]), WATCH_ICON / "icon-1024.png")
    write_json(WATCH_ICON / "Contents.json", appiconset_contents("icon-1024", "watchos", False))
    print(f"  wrote {WATCH_ICON.relative_to(REPO)}")

    render_docs_logo()

    DESIGN.mkdir(parents=True, exist_ok=True)
    (DESIGN / "currents-icon.svg").write_text(svg_document(ICON_SCALE, BG_DEFAULT, LINE, THEMES["ocean"]))
    (DESIGN / "currents-mark.svg").write_text(svg_document(LOGO_SCALE, None, LINE, THEMES["ocean"]))
    layers = DESIGN / "layers"
    layers.mkdir(exist_ok=True)
    for stale in layers.glob("*.svg"):
        stale.unlink()
    for layer in ("background", "fish", "eye"):
        (layers / f"{layer}.svg").write_text(
            svg_document(ICON_SCALE, BG_DEFAULT, LINE, THEMES["ocean"], layers={layer}))
    print(f"  wrote {DESIGN.relative_to(REPO)}/currents-icon.svg, currents-mark.svg + layers/")
    render_preview()
    print("Done.")


if __name__ == "__main__":
    main()
