# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10.4"]
# ///
"""Compose the App Store screenshots from the simulator captures.

Reads ios/AppStore/store-art.json and the raw captures (1320x2868 PNGs named
after their screen). Each slide is a field of the brand colour, a layered
lake scene (scripts/scenes.py, as in the header) or a full-bleed photo
with layers drawn on it in order: headline text, the
capture inside a drawn iPhone, pieces of a capture lifted onto white plates,
the app's own fish and lure art, and stickers. A slide with "span": 2 is
drawn as one wide picture and cut into two screenshots, so a phone can
straddle the join the way it does across the first two in the store.

    uv run scripts/store_art.py --shots screenshots/raw --out screenshots/store

Writes <out>/6.9/NN_name.png (1320x2868) and <out>/6.3/NN_name.png
(1206x2622), RGB with no alpha, as App Store Connect requires. The
"creative" entries are the product page Header, Search Results and
Universal art, drawn the same way at their own sizes into
<out>/creative/<name>.png; keep what matters inside each one's "safe" box,
which is all some devices show. The "events" entries are each in-app
event's card (16:9) and details page (9:16), written to
<out>/events/<slug>/event-card.png and event-details.png. Apple draws the
event's name and badge over these and adds its own gradient, so they carry
no text, logo, border or shade.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scenes  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "ios/Currents/Resources/Assets.xcassets"
FONTS = ROOT / "ios/AppStore/fonts"
PHOTOS = ROOT / "ios/AppStore/store-photos"

W, H = 1320, 2868          # 6.9-inch portrait
SMALL = (1206, 2622)       # 6.3-inch portrait

# The drawn iPhone 16 Pro Max, in capture pixels.
SCREEN_RADIUS = 168
BEZEL = 38
RIM = 13
EDGE = BEZEL + RIM
BUTTON_ROOM = 12
ISLAND = (378, 111, 33)    # width, height, top


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"InterDisplay-{weight}.ttf"), size)


# MARK: - Shapes


def rounded_mask(size: tuple[int, int], radius: float, scale: int = 4) -> Image.Image:
    """An anti-aliased rounded rectangle mask, drawn large and reduced."""
    w, h = size
    big = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, w * scale - 1, h * scale - 1), radius=radius * scale, fill=255)
    return big.resize(size, Image.LANCZOS)


def masked(img: Image.Image, mask: Image.Image) -> Image.Image:
    out = img.convert("RGBA")
    out.putalpha(ImageChops.multiply(out.getchannel("A"), mask))
    return out


def with_shadow(img: Image.Image, blur: int, offset: tuple[int, int], opacity: float,
                color=(4, 18, 34)) -> Image.Image:
    """The image over its own soft shadow, centred where the image was."""
    pad = blur * 3 + max(abs(offset[0]), abs(offset[1]))
    w, h = img.size
    out = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", img.size, color + (0,))
    shadow.putalpha(img.getchannel("A").point(lambda a: int(a * opacity)))
    out.alpha_composite(shadow, (pad + offset[0], pad + offset[1]))
    out = out.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(img, (pad, pad))
    return out


def place(canvas: Image.Image, img: Image.Image, center, angle: float = 0, shadow=None) -> None:
    """Paste `img` centred on `center`, turned `angle` degrees clockwise,
    clipped to the canvas."""
    if angle:
        img = img.rotate(-angle, resample=Image.BICUBIC, expand=True)
    if shadow:
        img = with_shadow(img, *shadow)
    x = round(center[0] - img.width / 2)
    y = round(center[1] - img.height / 2)
    left, top = max(0, -x), max(0, -y)
    right = min(img.width, canvas.width - x)
    bottom = min(img.height, canvas.height - y)
    if right <= left or bottom <= top:
        return
    canvas.alpha_composite(img.crop((left, top, right, bottom)), (x + left, y + top))


# MARK: - Device


def phone(shot: Image.Image, finish: str) -> Image.Image:
    """The capture inside a drawn iPhone 16 Pro Max, at capture scale, with
    room on both sides for the buttons."""
    shot = shot.convert("RGBA").resize((W, H), Image.LANCZOS)
    fw, fh = W + EDGE * 2, H + EDGE * 2
    outer_r = SCREEN_RADIUS + EDGE
    body = Image.new("RGBA", (fw + BUTTON_ROOM * 2, fh), (0, 0, 0, 0))
    ox = BUTTON_ROOM

    rim, rim_light = {
        "dark": (rgb("#3B3C40"), rgb("#76777C")),
        "light": (rgb("#C9C6C0"), rgb("#F2EFEA")),
    }[finish]

    # Action button and volume on the left; side button and Camera Control
    # on the right.
    draw = ImageDraw.Draw(body)
    for top, length in ((420, 120), (640, 220), (900, 220)):
        draw.rounded_rectangle((ox - 9, top, ox + 10, top + length), radius=8, fill=rim)
    for top, length in ((760, 330), (1560, 170)):
        draw.rounded_rectangle((ox + fw - 10, top, ox + fw + 9, top + length), radius=8, fill=rim)

    frame = Image.new("RGBA", (fw, fh), rim_light + (255,))
    inner = Image.new("RGBA", (fw - 4, fh - 4), rim + (255,))
    frame.alpha_composite(masked(inner, rounded_mask(inner.size, outer_r - 2)), (2, 2))
    bezel = Image.new("RGBA", (fw - RIM * 2, fh - RIM * 2), (6, 6, 8, 255))
    frame.alpha_composite(masked(bezel, rounded_mask(bezel.size, outer_r - RIM)), (RIM, RIM))
    frame.alpha_composite(masked(shot, rounded_mask((W, H), SCREEN_RADIUS)), (EDGE, EDGE))

    iw, ih, itop = ISLAND
    island = Image.new("RGBA", (iw, ih), (0, 0, 0, 255))
    frame.alpha_composite(masked(island, rounded_mask((iw, ih), ih / 2)), (EDGE + (W - iw) // 2, EDGE + itop))

    body.alpha_composite(masked(frame, rounded_mask(frame.size, outer_r)), (ox, 0))
    return body


# MARK: - Pieces


def plate(shot: Image.Image, box: list[int], radius: int, pad: int, outline, erase=()) -> Image.Image:
    """A piece of a capture on a white plate, the way a component is shown
    lifted out of the app. `erase` lists boxes, in capture pixels, painted
    over row by row with the background just right of each, for a control
    that means nothing once the piece is out of the app."""
    x, y, w, h = box
    shot = shot.convert("RGBA")
    if erase:
        shot = shot.copy()
        draw = ImageDraw.Draw(shot)
        for ex, ey, ew, eh in erase:
            for row in range(ey, ey + eh):
                draw.line([(ex, row), (ex + ew - 1, row)], fill=shot.getpixel((ex + ew + 4, row)))
    piece = shot.crop((x, y, x + w, y + h))
    pw, ph = w + pad * 2, h + pad * 2
    out = masked(Image.new("RGBA", (pw, ph), (255, 255, 255, 255)), rounded_mask((pw, ph), radius))
    out.alpha_composite(masked(piece, rounded_mask((w, h), max(radius - pad, 0))), (pad, pad))
    if outline:
        ring = masked(Image.new("RGBA", (pw + 8, ph + 8), outline + (255,)), rounded_mask((pw + 8, ph + 8), radius + 4))
        ring.alpha_composite(out, (4, 4))
        out = ring
    return out


def artwork(name: str, width: int, flip: bool = False) -> Image.Image:
    """A fish or lure drawing from the asset catalogue, `width` pixels wide."""
    folder = "Fish" if name.startswith("fish_") else "Lures"
    img = Image.open(ASSETS / folder / f"{name}.imageset" / f"{name}.png").convert("RGBA")
    img = img.crop(img.getbbox())
    img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=50, threshold=2))
    return ImageOps.mirror(img) if flip else img


def logo(height: int, color) -> Image.Image:
    img = Image.open(ASSETS / "Logo.imageset/Logo@3x.png").convert("RGBA")
    img = img.crop(img.getbbox())
    img = img.resize((round(img.width * height / img.height), height), Image.LANCZOS)
    solid = Image.new("RGBA", img.size, color + (255,))
    solid.putalpha(img.getchannel("A"))
    return solid


def cover(path: Path, size: tuple[int, int], focus) -> Image.Image:
    """The photo scaled to fill `size`, cropped around `focus` (0 to 1)."""
    img = Image.open(path).convert("RGB")
    scale = max(size[0] / img.width, size[1] / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    x = round((img.width - size[0]) * focus[0])
    y = round((img.height - size[1]) * focus[1])
    return img.crop((x, y, x + size[0], y + size[1])).convert("RGBA")


# MARK: - Type


def text_width(text: str, f: ImageFont.FreeTypeFont, tracking: float) -> float:
    return f.getlength(text) + tracking * f.size * max(len(text) - 1, 0)


def draw_text(canvas: Image.Image, text: str, f: ImageFont.FreeTypeFont, xy, color, tracking: float = 0) -> None:
    """Text with tracking (a fraction of the size). Each glyph is placed by
    measuring the prefix before it, so kerning is kept."""
    draw = ImageDraw.Draw(canvas)
    x, y = xy
    for i, ch in enumerate(text):
        draw.text((x + f.getlength(text[:i]) + tracking * f.size * i, y), ch, font=f, fill=color)


def sticker(text: str, size: int, fill, ink, angle: float = 0) -> Image.Image:
    """A short label in the second colour with an ink border, like a
    printed sticker."""
    f = font("ExtraBold", size)
    pad_x, pad_y = round(size * 0.5), round(size * 0.3)
    w = round(text_width(text, f, -0.01) + pad_x * 2)
    h = round(size * 1.16 + pad_y * 2)
    b = 6
    img = masked(Image.new("RGBA", (w + b * 2, h + b * 2), ink + (255,)), rounded_mask((w + b * 2, h + b * 2), h * 0.28 + b))
    img.alpha_composite(masked(Image.new("RGBA", (w, h), fill + (255,)), rounded_mask((w, h), h * 0.28)), (b, b))
    asc, _ = f.getmetrics()
    draw_text(img, text, f, (b + pad_x, b + (h - asc) / 2 - size * 0.05), ink, -0.01)
    return img.rotate(-angle, resample=Image.BICUBIC, expand=True) if angle else img


# MARK: - Slides


def color(theme: dict, name: str):
    return rgb(theme.get(name, name))


def draw_slide(spec: dict, theme: dict, shots: Path) -> Image.Image:
    span = spec.get("span", 1)
    size = tuple(spec["size"]) if "size" in spec else (W * span, H)
    if "photo" in spec:
        canvas = cover(PHOTOS / spec["photo"], size, spec.get("focus", (0.5, 0.5)))
        if spec.get("blur"):
            # Out of focus behind the phone, the way a camera sees it.
            canvas = canvas.filter(ImageFilter.GaussianBlur(spec["blur"]))
    elif "scene" in spec:
        canvas = scenes.Scene(spec["scene"], theme, size).frame(0)
    else:
        canvas = Image.new("RGBA", size, color(theme, spec.get("field", "field")) + (255,))

    finish = theme.get("device", "light")
    last_phone = None   # centre, scale, angle and capture of the latest phone

    for layer in spec["layers"]:
        kind = layer["type"]
        if kind == "text":
            f = font(layer.get("weight", "ExtraBold"), layer["size"])
            ink = color(theme, layer.get("color", "ink"))
            x, y = layer["at"]
            step = f.size * layer.get("leading", 1.0)
            tracking = layer.get("tracking", -0.025)
            for i, line in enumerate(layer["lines"]):
                w = text_width(line, f, tracking)
                lx = {"left": x, "center": x - w / 2, "right": x - w}[layer.get("align", "left")]
                draw_text(canvas, line, f, (lx, y + i * step), ink, tracking)
        elif kind == "logo":
            ink = color(theme, layer.get("color", "ink"))
            h = layer.get("height", 92)
            mark = logo(h, ink)
            x, y = layer["at"]
            canvas.alpha_composite(mark, (x, y))
            draw_text(canvas, "Currents", font("Bold", round(h * 0.9)), (x + mark.width + h * 0.28, y + h * 0.02), ink, -0.02)
        elif kind == "facts":
            ink = color(theme, layer.get("color", "ink"))
            x, y = layer["at"]
            size = layer.get("size", 96)
            fb, fs = font("ExtraBold", size), font("SemiBold", round(size * 0.46))
            for big, small in layer["items"]:
                draw_text(canvas, big, fb, (x, y), ink, -0.02)
                draw_text(canvas, small, fs, (x + 4, y + size * 1.12), ink, -0.005)
                x += max(text_width(big, fb, -0.02), text_width(small, fs, -0.005)) + layer.get("gap", 120)
        elif kind == "phone":
            shot = Image.open(shots / f"{layer['screen']}.png")
            dev = phone(shot, layer.get("finish", finish))
            scale = layer["scale"]
            dev = dev.resize((round(dev.width * scale), round(dev.height * scale)), Image.LANCZOS)
            place(canvas, dev, layer["center"], layer.get("angle", 0), (50, (0, 40), 0.36))
            last_phone = (layer["center"], scale, layer.get("angle", 0), shot)
        elif kind == "pop":
            # A piece lifted straight up out of the last phone's screen: over
            # its own spot, a little larger, turned with the phone.
            (cx, cy), scale, angle, shot = last_phone
            x, y, w, h = layer["box"]
            dx = (x + w / 2 - W / 2) * scale
            dy = (y + h / 2 - H / 2) * scale
            t = math.radians(angle)
            center = (cx + dx * math.cos(t) - dy * math.sin(t), cy + dx * math.sin(t) + dy * math.cos(t))
            piece = plate(shot, layer["box"], layer.get("radius", 60), layer.get("pad", 0),
                          rgb(layer["outline"]) if layer.get("outline") else None, layer.get("erase", ()))
            k = scale * layer.get("lift", 1.1)
            piece = piece.resize((round(piece.width * k), round(piece.height * k)), Image.LANCZOS)
            place(canvas, piece, center, angle + layer.get("turn", 0), (36, (0, 28), 0.3))
        elif kind == "card":
            shot = Image.open(shots / f"{layer['screen']}.png")
            piece = plate(shot, layer["box"], layer.get("radius", 60), layer.get("pad", 28),
                          rgb(layer["outline"]) if layer.get("outline") else None, layer.get("erase", ()))
            k = layer.get("scale", 1.0)
            piece = piece.resize((round(piece.width * k), round(piece.height * k)), Image.LANCZOS)
            place(canvas, piece, layer["center"], layer.get("angle", 0), (36, (0, 28), 0.26))
        elif kind == "art":
            img = artwork(layer["name"], layer["width"], layer.get("flip", False))
            place(canvas, img, layer["center"], layer.get("angle", 0), (16, (0, 12), 0.2))
        elif kind == "shade":
            # A dark wash fading in from one edge, so white type reads on a
            # photo.
            size_px, opacity = layer["size"], layer.get("opacity", 0.5)
            ramp = Image.linear_gradient("L").resize((1, size_px))
            if layer.get("edge", "top") == "top":
                ramp = ImageOps.flip(ramp)
            ramp = ramp.point(lambda v: round(v * opacity)).resize((canvas.width, size_px))
            wash = Image.new("RGBA", (canvas.width, size_px), (0, 0, 0, 0))
            wash.putalpha(ramp)
            top = 0 if layer.get("edge", "top") == "top" else canvas.height - size_px
            canvas.alpha_composite(wash, (0, top))
        elif kind == "sticker":
            img = sticker(layer["text"], layer.get("size", 64), color(theme, "sticker"), color(theme, "ink"),
                          layer.get("angle", 0))
            place(canvas, img, layer["center"], 0, (14, (0, 10), 0.22))
        else:
            raise ValueError(f"unknown layer {kind}")
    return canvas.convert("RGB")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--shots", type=Path, required=True, help="folder of <screen>.png captures")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--config", type=Path, default=ROOT / "ios/AppStore/store-art.json")
    ap.add_argument("--only", nargs="*", help="slide names to render")
    args = ap.parse_args()

    config = json.loads(args.config.read_text())
    theme = config["theme"]
    # A slide's "scene" can name one of the shared "scenes".
    named = config.get("scenes", {})
    for spec in [*config.get("creative", []), *config["slides"],
                 *(e[k] for e in config.get("events", []) for k in ("card", "details"))]:
        if isinstance(spec.get("scene"), str):
            spec["scene"] = named[spec["scene"]]
    for d in ("6.9", "6.3"):
        (args.out / d).mkdir(parents=True, exist_ok=True)
    have = {p.stem for p in args.shots.glob("*.png")}

    for spec in config.get("creative", []):
        if args.only and spec["name"] not in args.only:
            continue
        missing = {l["screen"] for l in spec["layers"] if "screen" in l} - have
        if missing:
            print(f"skip {spec['name']}: no capture for {', '.join(sorted(missing))}")
            continue
        (args.out / "creative").mkdir(parents=True, exist_ok=True)
        draw_slide(spec, theme, args.shots).save(args.out / "creative" / f"{spec['name']}.png", optimize=True)
        print(f"wrote creative/{spec['name']}.png")

    for event in config.get("events", []):
        if args.only and event["slug"] not in args.only:
            continue
        for kind, filename in (("card", "event-card.png"), ("details", "event-details.png")):
            spec = event[kind]
            missing = {l["screen"] for l in spec["layers"] if "screen" in l} - have
            if missing:
                print(f"skip events/{event['slug']}/{filename}: no capture for {', '.join(sorted(missing))}")
                continue
            folder = args.out / "events" / event["slug"]
            folder.mkdir(parents=True, exist_ok=True)
            draw_slide(spec, theme, args.shots).save(folder / filename, optimize=True)
            print(f"wrote events/{event['slug']}/{filename}")

    number = 0
    for spec in config["slides"]:
        names = spec.get("names", [spec.get("name")])
        first = number + 1
        number += len(names)
        if args.only and not set(args.only) & set(names):
            continue
        missing = {l["screen"] for l in spec["layers"] if "screen" in l} - have
        if missing:
            print(f"skip {', '.join(names)}: no capture for {', '.join(sorted(missing))}")
            continue
        img = draw_slide(spec, theme, args.shots)
        for i, name in enumerate(names):
            part = img.crop((i * W, 0, (i + 1) * W, H))
            file = f"{first + i:02d}_{name}.png"
            part.save(args.out / "6.9" / file, optimize=True)
            part.resize(SMALL, Image.LANCZOS).save(args.out / "6.3" / file, optimize=True)
            print(f"wrote {file}")


if __name__ == "__main__":
    main()
