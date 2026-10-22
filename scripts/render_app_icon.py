#!/usr/bin/env python3
"""
Render every Currents icon asset from one vector definition of the mark.

The mark is a sleek fish, tilted slightly upward as if rising, with a single
"current" stroke running along its flank. The geometry lives in this file as
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
  design/icon/layers/{background,fish,current}.svg                 Icon Composer layers
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

FISH = "#F5F5F7"
FISH_TINTED = "#FFFFFF"
CURRENT_TINTED = "#9A9A9E"            # greys keep the two-tone in tinted mode

# Accent per theme = the light stop of ThemeOption.gradient in LiquidGlass.swift,
# so the icon's current line and the in-app wordmark gradient agree.
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

# Transparent in-app logo imagesets -> theme of the current line
LOGO_SETS = {
    "Logo": "ocean",
    "LogoGreen": "forest",
    "LogoPurple": "amethyst",
    "LogoGold": "gold",
}

# --------------------------------------------------------------------------
# Geometry (unit square, fish facing right, un-tilted)
# --------------------------------------------------------------------------

# Closed outline as (point, ctrl_out, ctrl_in) style cubic segments:
# each entry is the end point of a cubic plus the two control points that lead
# to it from the previous end point. Three corners (nose, two tail tips) are
# sharp here and get rounded geometrically by `rounded_outline` below.
_RAW = [
    # end point,     ctrl1,         ctrl2
    ((0.95, 0.50), None, None),                       # nose (start)
    ((0.56, 0.29), (0.86, 0.36), (0.70, 0.29)),       # over the back
    ((0.30, 0.44), (0.46, 0.29), (0.37, 0.36)),       # down to the tail root
    ((0.09, 0.26), (0.25, 0.38), (0.17, 0.30)),       # upper tail tip
    ((0.21, 0.50), (0.13, 0.34), (0.17, 0.43)),       # fork notch
    ((0.09, 0.74), (0.17, 0.57), (0.13, 0.66)),       # lower tail tip
    ((0.30, 0.56), (0.17, 0.70), (0.25, 0.62)),       # back to the tail root
    ((0.56, 0.71), (0.37, 0.64), (0.46, 0.71)),       # along the belly
    ((0.95, 0.50), (0.70, 0.71), (0.86, 0.64)),       # up to the nose (close)
]
_ROUND = {0: 0.030, 3: 0.028, 5: 0.028}   # corner index -> rounding radius

EYE = (0.80, 0.45, 0.030)                 # cx, cy, r
CURRENT = (0.40, 0.72, 0.515, 0.035)      # x0, x1, y, amplitude (one period)
CURRENT_WIDTH = 0.046

TILT_DEG = -8.0                           # nose up: "rising to the surface"
ICON_SCALE = 0.84                         # mark width as a fraction of the icon
WATCH_SCALE = 0.70                        # stays inside the circular mask
LOGO_SCALE = 0.96                         # transparent imagesets: fill the box


def _unit(v):
    n = math.hypot(*v)
    return (v[0] / n, v[1] / n)


def rounded_outline():
    """Return the closed outline as a list of ('M'|'C'|'Z', pts...) in unit coords."""
    n = len(_RAW) - 1  # last entry closes back to the first point
    # Work on a ring of corners 0..n-1 where corner i is the end point of seg i.
    pts = [p for p, _, _ in _RAW[:-1]]
    ctrls = []  # ctrls[i] = (c1, c2) for the segment from corner i-1 to corner i
    for i in range(1, len(_RAW)):
        ctrls.append(_RAW[i][1:])
    # segment i runs corner i -> corner i+1 (mod n) with ctrls[i]
    segs = [(pts[i], ctrls[i][0], ctrls[i][1], pts[(i + 1) % n]) for i in range(n)]

    # Trim segments at rounded corners and insert a small cubic for the corner.
    out = []
    K = 0.55
    for i in range(n):
        p0, c1, c2, p1 = segs[i]
        j = (i + 1) % n
        if i in _ROUND:  # trim the start of this segment
            r = _ROUND[i]
            d = _unit((c1[0] - p0[0], c1[1] - p0[1]))
            p0 = (p0[0] + r * d[0], p0[1] + r * d[1])
        if j in _ROUND:  # trim the end of this segment
            r = _ROUND[j]
            d = _unit((c2[0] - p1[0], c2[1] - p1[1]))
            p1 = (p1[0] + r * d[0], p1[1] + r * d[1])
        out.append(("C", c1, c2, p1, p0))
        if j in _ROUND:
            tip = pts[j]
            nxt = segs[j]
            r = _ROUND[j]
            d2 = _unit((nxt[1][0] - tip[0], nxt[1][1] - tip[1]))
            s = (tip[0] + r * d2[0], tip[1] + r * d2[1])
            k1 = (p1[0] + K * (tip[0] - p1[0]), p1[1] + K * (tip[1] - p1[1]))
            k2 = (s[0] + K * (tip[0] - s[0]), s[1] + K * (tip[1] - s[1]))
            out.append(("C", k1, k2, s, p1))

    path = [("M", out[0][4])]
    for cmd, c1, c2, p1, _ in out:
        path.append(("C", c1, c2, p1))
    path.append(("Z",))
    return path


def current_path():
    x0, x1, y, amp = CURRENT
    seg = (x1 - x0) / 2
    pts = [("M", (x0, y))]
    for i in range(2):
        a = x0 + i * seg
        b = a + seg
        s = -1 if i == 0 else 1
        pts.append(("C", (a + seg * 0.36, y + s * amp), (b - seg * 0.36, y + s * amp), (b, y)))
    return pts


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

def svg_document(scale, bg, fish, current, *, eye_fill=None, layers=None):
    """Full icon SVG. `bg` is (top, bottom) or None for transparent.

    `layers` may be a subset of {"background", "fish", "current"} to emit a
    single Icon Composer layer.
    """
    layers = layers or {"background", "fish", "current"}
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
        ex, ey, er = EYE
        cx, cy = t((ex, ey))
        d = to_svg_d(rounded_outline(), t)
        # Eye as a sub-path with even-odd fill so it is a real hole (works on
        # transparent exports and matches the SwiftUI eoFill).
        hole = (f" M{cx + er * scale:.4f},{cy:.4f} "
                f"A{er * scale:.4f},{er * scale:.4f} 0 1 0 {cx - er * scale:.4f},{cy:.4f} "
                f"A{er * scale:.4f},{er * scale:.4f} 0 1 0 {cx + er * scale:.4f},{cy:.4f} Z")
        body.append(f'<path d="{d}{hole}" fill="{fish}" fill-rule="evenodd"/>')
    if "current" in layers:
        d = to_svg_d(current_path(), t)
        body.append(f'<path d="{d}" fill="none" stroke="{current}" '
                    f'stroke-width="{CURRENT_WIDTH * scale:.4f}" stroke-linecap="round"/>')
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
    render_png(svg_document(ICON_SCALE, BG_DEFAULT, FISH, accent), out_dir / f"{prefix}.png")
    render_png(svg_document(ICON_SCALE, BG_DARK, FISH, accent), out_dir / f"{prefix}-dark.png")
    render_png(svg_document(ICON_SCALE, BG_TINTED, FISH_TINTED, CURRENT_TINTED),
               out_dir / f"{prefix}-tinted.png")
    write_json(out_dir / "Contents.json", appiconset_contents(prefix, "ios", True))
    print(f"  wrote {out_dir.relative_to(REPO)}")


def render_logo_set(name: str, theme: str):
    out_dir = ASSETS / f"{name}.imageset"
    svg = svg_document(LOGO_SCALE, None, FISH, THEMES[theme])
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
    render_png(svg_document(ICON_SCALE, BG_DEFAULT, FISH, THEMES["ocean"]), tmp)
    im = Image.open(tmp).convert("RGBA")
    im.putalpha(squircle_mask(SIZE))
    im.save(DOCS_LOGO)
    tmp.unlink()
    print(f"  wrote {DOCS_LOGO.relative_to(REPO)}")


def render_preview():
    from PIL import Image, ImageDraw
    tile, gap, pad = 160, 28, 40
    themes = list(THEMES)
    rows = [("default", BG_DEFAULT, FISH, None), ("dark", BG_DARK, FISH, None),
            ("tinted", BG_TINTED, FISH_TINTED, CURRENT_TINTED)]
    W = pad * 2 + 120 + len(themes) * (tile + gap)
    H = pad * 2 + len(rows) * (tile + gap) + 220
    sheet = Image.new("RGB", (W, H), (236, 236, 241))
    d = ImageDraw.Draw(sheet)
    mask = squircle_mask(tile)
    tmp = DESIGN / "_tmp.png"
    for r, (label, bg, fish, cur) in enumerate(rows):
        y = pad + r * (tile + gap)
        d.text((pad, y + tile // 2), label, fill=(60, 60, 70), anchor="lm")
        for c, theme in enumerate(themes):
            x = pad + 120 + c * (tile + gap)
            render_png(svg_document(ICON_SCALE, bg, fish, cur or THEMES[theme]), tmp, tile)
            sheet.paste(Image.open(tmp).convert("RGB"), (x, y), mask)
            if r == 0:
                d.text((x + tile // 2, y - 14), theme, fill=(60, 60, 70), anchor="mm")
    # size ladder on light and dark
    y = pad + len(rows) * (tile + gap) + 20
    d.text((pad, y + 60), "sizes", fill=(60, 60, 70), anchor="lm")
    render_png(svg_document(ICON_SCALE, BG_DEFAULT, FISH, THEMES["ocean"]), tmp, 256)
    big = Image.open(tmp).convert("RGB")
    x = pad + 120
    for px in (29, 40, 58, 76, 120, 180):
        im = big.resize((px, px), Image.LANCZOS)
        sheet.paste(im, (x, y + 90 - px // 2), squircle_mask(px))
        d.text((x + px // 2, y + 170), f"{px}px", fill=(60, 60, 70), anchor="mm")
        x += px + 34
    dark = Image.new("RGB", (W - x - pad, 200), (28, 28, 30))
    sheet.paste(dark, (x, y))
    render_png(svg_document(LOGO_SCALE, None, FISH, THEMES["ocean"]), tmp, 150)
    logo = Image.open(tmp).convert("RGBA")
    sheet.paste(logo, (x + 20, y + 25), logo)
    render_png(svg_document(WATCH_SCALE, BG_WATCH, FISH, THEMES["ocean"]), tmp, 150)
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
    for seg in rounded_outline():
        cmd, *ps = seg
        if cmd == "M":
            lines.append(f"        p.move(to: {pt(ps[0])})")
        elif cmd == "C":
            lines.append(f"        p.addCurve(to: {pt(ps[2])},")
            lines.append(f"                   control1: {pt(ps[0])},")
            lines.append(f"                   control2: {pt(ps[1])})")
        else:
            lines.append("        p.closeSubpath()")
    ex, ey, er = EYE
    cx, cy = t((ex, ey))
    lines.append("        // Eye: a separate sub-path; fill with eoFill so it is a hole.")
    lines.append(f"        p.addEllipse(in: CGRect(x: w * {cx - er:.4f}, y: h * {cy - er:.4f}, "
                 f"width: w * {2 * er:.4f}, height: h * {2 * er:.4f}))")
    lines.append("        return p")
    lines.append("    }")
    fish = "\n".join(lines)

    lines = ["    func path(in rect: CGRect) -> Path {",
             "        var p = Path()",
             "        let w = rect.width, h = rect.height"]
    for seg in current_path():
        cmd, *ps = seg
        if cmd == "M":
            lines.append(f"        p.move(to: {pt(ps[0])})")
        else:
            lines.append(f"        p.addCurve(to: {pt(ps[2])},")
            lines.append(f"                   control1: {pt(ps[0])},")
            lines.append(f"                   control2: {pt(ps[1])})")
    lines.append("        return p")
    lines.append("    }")
    current = "\n".join(lines)
    return f"""import SwiftUI

// Generated by `python scripts/render_app_icon.py --swift` — do not hand-edit.
// The same control points render the App Store / Home Screen icon PNGs, so the
// in-app logo and the icon are guaranteed to be the same mark.

/// The fish body (tilted {abs(TILT_DEG):g}° nose-up) with the eye as an even-odd hole.
/// Fill with `FillStyle(eoFill: true)`.
struct CurrentsFishShape: Shape {{
{fish}
}}

/// The single "current" running along the flank. Stroke with round caps at
/// `size * CurrentsMark.currentLineWidth`.
struct CurrentsCurrentShape: Shape {{
{current}
}}

/// The Currents mark: fish filled in `tint`, current line stroked in `accent`.
///
/// Inside the app the fish takes the theme colour and the current is white
/// (the inverse of the Home Screen icon, where the fish is white and the
/// current carries the theme colour). Square; size it with `.frame(width:height:)`.
struct CurrentsMark: View {{
    var tint: Color
    var accent: Color = .white

    static let currentLineWidth: CGFloat = {CURRENT_WIDTH:.3f}

    var body: some View {{
        GeometryReader {{ geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {{
                CurrentsFishShape()
                    .fill(tint, style: FillStyle(eoFill: true))
                CurrentsCurrentShape()
                    .stroke(accent, style: StrokeStyle(lineWidth: side * Self.currentLineWidth,
                                                       lineCap: .round))
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

    render_png(svg_document(WATCH_SCALE, BG_WATCH, FISH, THEMES["ocean"]), WATCH_ICON / "icon-1024.png")
    write_json(WATCH_ICON / "Contents.json", appiconset_contents("icon-1024", "watchos", False))
    print(f"  wrote {WATCH_ICON.relative_to(REPO)}")

    render_docs_logo()

    DESIGN.mkdir(parents=True, exist_ok=True)
    (DESIGN / "currents-icon.svg").write_text(svg_document(ICON_SCALE, BG_DEFAULT, FISH, THEMES["ocean"]))
    layers = DESIGN / "layers"
    layers.mkdir(exist_ok=True)
    for layer in ("background", "fish", "current"):
        (layers / f"{layer}.svg").write_text(
            svg_document(ICON_SCALE, BG_DEFAULT, FISH, THEMES["ocean"], layers={layer}))
    print(f"  wrote {DESIGN.relative_to(REPO)}/currents-icon.svg + layers/")
    render_preview()
    print("Done.")


if __name__ == "__main__":
    main()
