"""Layered scenes in the brand's colours, behind the store art and in the
animated header.

A scene is a sky and a stack of silhouettes, each a shade further from the
sky towards the deep colour: far hills, the water, reeds along the bank,
nearer water. Each layer repeats along x every `period` pixels and moves
`speed` whole periods over the loop, so far layers drift slowly, near ones
faster, and the last frame of a loop runs straight into the first. Stills
are the scene at t = 0.

Spec, all positions as fractions of the canvas height unless noted:

    {"sky": "field", "sky_top": "pale", "sky_to": 0.5, "base": "field", "deep": "navy",
     "sun": {"at": [0.5, 0.3], "r": 0.08, "color": "sun", "ring": true},
     "stars": 40, "rays": 5,
     "layers": [{"kind": "hills" | "water" | "reeds" | "school" | "bubbles",
                 "y": 0.6, "amp": 0.02, "period": 1280, "speed": 1,
                 "shade": 0.3 or "color": "navy", ...}]}

Layers are mixed from "base" (the sky's colour unless given) towards
"deep" by their "shade", so a yellow evening sky can sit over blue water.

Layer kinds:
    hills    rolling ground, filled to the bottom
    water    a wavy surface, filled to the bottom, with optional "ripples"
    pines    rolling ground with stands of pine trees, "height" tall
    boat     a rowboat with an angler, waterline at y, at "at" along the period
    reeds    blades standing on y, "height" tall, with a "cattails" share of cattails
    school   the Currents mark as small fish swimming at y, "count" of them
    bubbles  rising rings, filled from y to the bottom ("rise" periods a loop)
"""

from __future__ import annotations

import math
import random
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw

LOGO = Path(__file__).resolve().parent.parent / "ios/Currents/Resources/Assets.xcassets/Logo.imageset/Logo@3x.png"
SUPER = 2   # silhouettes are drawn this much larger, then reduced, for smooth edges


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, f: float) -> tuple[int, int, int]:
    return tuple(round(x + (y - x) * f) for x, y in zip(a, b))


def paint(theme: dict, name: str) -> tuple[int, int, int]:
    return rgb(theme.get(name, name))


# MARK: - Shapes


def profile(period: int, amp: float, harmonics, seed: int) -> list[float]:
    """Heights along one period, at SUPER scale, from whole-number harmonics
    so the ends meet."""
    rng = random.Random(seed)
    phases = [(k, w, rng.uniform(0, 2 * math.pi)) for k, w in harmonics]
    total = sum(w for _, w, _ in phases)
    n = period * SUPER
    return [amp * SUPER * sum(w * math.sin(2 * math.pi * k * i / n + p) for k, w, p in phases) / total
            for i in range(n + 1)]


def filled(period: int, height: int, top: float, heights: list[float], color,
           ripples: dict | None = None, ripple_color=None, seed: int = 0) -> Image.Image:
    """One period of a layer whose top edge is `top` plus the profile,
    filled to the bottom. Water can carry ripples: short flat strokes in a
    lighter shade, "count" of them within "depth" (of the height) below the
    edge, longer and further apart nearer the viewer."""
    w, h = period * SUPER, height * SUPER
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    y0 = top * SUPER
    points = [(i, y0 - heights[i]) for i in range(w + 1)] + [(w, h), (0, h)]
    draw.polygon(points, fill=color + (255,))
    if ripples:
        rng = random.Random(seed)
        depth = ripples.get("depth", 0.1) * h
        thick = ripples.get("thick", 6) * SUPER
        for _ in range(ripples.get("count", 10)):
            f = rng.uniform(0.12, 1.0)
            ry = y0 + depth * f
            length = (ripples.get("length", 160) * SUPER) * (0.4 + 0.8 * f) * rng.uniform(0.6, 1.2)
            rx = rng.uniform(0, w)
            th = thick * (0.6 + 0.6 * f)
            for shift in (-w, 0, w):
                draw.rounded_rectangle((rx + shift, ry - th / 2, rx + shift + length, ry + th / 2), radius=th / 2,
                                       fill=ripple_color + (255,))
    return img.reduce(SUPER)


def reeds(period: int, height: int, base: float, tall: float, color, seed: int, density: float,
          cattails: float = 0.3) -> Image.Image:
    """Clumps of reeds and cattails along one period, drawn again one period
    to each side so a clump on the seam tiles cleanly."""
    rng = random.Random(seed)
    w, h = period * SUPER, height * SUPER
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = SUPER
    y = base * s
    clumps = []
    x = rng.uniform(0, period * 0.3)
    while x < period:
        clumps.append(x)
        x += rng.uniform(260, 520) / density
    blades = []
    for cx in clumps:
        for _ in range(rng.randint(5, 9)):
            bx = cx + rng.uniform(-70, 70)
            bh = tall * rng.uniform(0.45, 1.0)
            lean = rng.uniform(-0.28, 0.28) * bh
            bw = rng.uniform(9, 15) * tall / 200
            cattail = rng.random() < cattails
            blades.append((bx, bh, lean, bw, cattail))
    for shift in (-period, 0, period):
        for bx, bh, lean, bw, cattail in blades:
            x0 = (bx + shift) * s
            if x0 < -bw * s * 4 - abs(lean) * s or x0 > w + bw * s * 4 + abs(lean) * s:
                continue
            # A blade: a curved taper from the base to the tip.
            left, right = [], []
            for i in range(13):
                f = i / 12
                cx_ = x0 + lean * s * f * f
                cy_ = y - bh * s * f
                half = bw * s * 0.5 * (1 - f) ** 0.8
                left.append((cx_ - half, cy_))
                right.append((cx_ + half, cy_))
            if not cattail:
                draw.polygon(left + right[::-1], fill=color + (255,))
            if cattail:
                # A slim seed head two thirds of the way up, with the stem's
                # spike above it.
                lean_at = lambda f: x0 + lean * s * 0.4 * f
                stem = [(lean_at(f / 10), y - bh * s * f / 10) for f in range(11)]
                draw.line(stem, fill=color + (255,), width=max(2, round(bw * s * 0.3)))
                head_w = bw * s * 0.95
                head = [(lean_at(f), y - bh * s * f) for f in (0.6, 0.86)]
                draw.line(head, fill=color + (255,), width=round(head_w))
                for (hx, hy) in head:
                    draw.ellipse((hx - head_w / 2, hy - head_w / 2, hx + head_w / 2, hy + head_w / 2), fill=color + (255,))
    return img.reduce(SUPER)


def pines(period: int, height: int, ground: float, amp: float, tall: float, color, seed: int, density: float,
          group: int = 5) -> Image.Image:
    """Rolling ground filled to the bottom with stands of pines along it:
    the trees are stacked tiers, in groups of two to `group`, tallest in the
    middle of a group."""
    rng = random.Random(seed)
    heights = profile(period, amp, [(1, 1.0), (2, 0.4)], seed)
    w, h = period * SUPER, height * SUPER
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = SUPER
    points = [(i, ground * s - heights[i]) for i in range(w + 1)] + [(w, h), (0, h)]
    draw.polygon(points, fill=color + (255,))

    trees = []
    x = rng.uniform(0, 200)
    while x < period:
        count = rng.randint(min(2, group), group)
        for j in range(count):
            middle = 1 - abs(j - (count - 1) / 2) / max(1, count / 2)
            th = tall * rng.uniform(0.55, 0.8) * (0.7 + 0.3 * middle)
            trees.append((x + j * tall * rng.uniform(0.26, 0.36), th))
        x += count * tall * 0.3 + rng.uniform(220, 520) / density

    def ground_at(px: float) -> float:
        i = int(px * s) % w
        return ground * s - heights[i]

    for shift in (-period, 0, period):
        for tx, th in trees:
            cx = (tx + shift) * s
            if cx < -tall * s or cx > w + tall * s:
                continue
            base = ground_at(tx) + 6 * s
            tiers = 4
            width = th * 0.42 * s
            draw.rectangle((cx - th * 0.025 * s, base - th * 0.2 * s, cx + th * 0.025 * s, base), fill=color + (255,))
            for k in range(tiers):
                bottom = base - th * s * (0.12 + 0.2 * k)
                top = bottom - th * s * 0.42
                half = width * (1 - k * 0.2) / 2
                draw.polygon([(cx - half, bottom), (cx + half, bottom), (cx, top)], fill=color + (255,))
    return img.reduce(SUPER)


def boat(period: int, height: int, water: float, size: float, at: float, color, sunk: float = 40) -> Image.Image:
    """A rowboat with an angler casting, its waterline at `water`. Out on
    open water give it a small "sunk" (how far the hull reaches below the
    line) and the speed of the water it sits on; at a far edge, put it just
    before that water layer and let the surface cover the hull."""
    w, h = period * SUPER, height * SUPER
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = SUPER * size / 100
    cx, y = at * w, water * SUPER
    fill = color + (255,)
    # Hull: a shallow trapezoid with a raised bow.
    draw.polygon([(cx - 70 * s, y - 22 * s), (cx + 62 * s, y - 22 * s), (cx + 84 * s, y - 36 * s),
                  (cx + 54 * s, y + sunk * s), (cx - 58 * s, y + sunk * s)], fill=fill)
    # The angler, seated towards the stern.
    ax = cx - 24 * s
    draw.ellipse((ax - 11 * s, y - 86 * s, ax + 11 * s, y - 64 * s), fill=fill)
    draw.polygon([(ax - 15 * s, y - 22 * s), (ax + 17 * s, y - 22 * s), (ax + 12 * s, y - 62 * s), (ax - 10 * s, y - 62 * s)], fill=fill)
    # A cap brim and the rod, bent a little, with its line falling ahead.
    draw.polygon([(ax - 2 * s, y - 84 * s), (ax + 20 * s, y - 80 * s), (ax + 2 * s, y - 78 * s)], fill=fill)
    rod = [(ax + 10 * s, y - 48 * s), (ax + 70 * s, y - 118 * s), (ax + 120 * s, y - 156 * s), (ax + 150 * s, y - 168 * s)]
    draw.line(rod, fill=fill, width=max(2, round(4 * s)), joint="curve")
    draw.line([rod[-1], (ax + 196 * s, y + 2 * s)], fill=color + (200,), width=max(1, round(1.6 * s)))
    return img.reduce(SUPER)


@lru_cache(maxsize=8)
def mark(height: int) -> Image.Image:
    img = Image.open(LOGO).convert("RGBA")
    img = img.crop(img.getbbox())
    return img.resize((round(img.width * height / img.height), height), Image.LANCZOS)


def tint(img: Image.Image, color, alpha: float = 1.0) -> Image.Image:
    solid = Image.new("RGBA", img.size, color + (0,))
    solid.putalpha(img.getchannel("A").point(lambda v: round(v * alpha)))
    return solid


def school(period: int, height: int, y: float, size: float, count: int, color, seed: int, facing: int) -> Image.Image:
    """Small fish in the shape of the mark, loosely grouped, all facing one way."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (period, height), (0, 0, 0, 0))
    for i in range(count):
        fh = round(size * rng.uniform(0.6, 1.0))
        fish = tint(mark(fh), color)
        # The mark points up and right; level it into a swimming fish.
        fish = fish.rotate(-38 if facing > 0 else 38, resample=Image.BICUBIC, expand=True)
        if facing < 0:
            fish = fish.transpose(Image.FLIP_LEFT_RIGHT).rotate(76, resample=Image.BICUBIC, expand=True)
        fx = (period * (i + rng.uniform(0.1, 0.9)) / count)
        fy = y + rng.uniform(-1, 1) * size * 1.2
        for shift in (-period, 0, period):
            img.alpha_composite(fish, (round(fx + shift - fish.width / 2), round(fy - fish.height / 2)))
    return img


def bubbles(period: int, height: int, top: float, count: int, size: float, color, seed: int) -> Image.Image:
    """Rings scattered over one period square, tiling both ways."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (period * SUPER, period * SUPER), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        r = size * rng.uniform(0.35, 1.0) * SUPER
        bx, by = rng.uniform(0, period * SUPER), rng.uniform(0, period * SUPER)
        for sx in (-period * SUPER, 0, period * SUPER):
            for sy in (-period * SUPER, 0, period * SUPER):
                draw.ellipse((bx + sx - r, by + sy - r, bx + sx + r, by + sy + r),
                             outline=color + (150,), width=max(2, round(r * 0.22)))
    return img.reduce(SUPER)


# MARK: - Scene


class Scene:
    """A scene built once at one size; `frame(t)` places each layer for time
    t within the loop."""

    def __init__(self, spec: dict, theme: dict, size: tuple[int, int], loop: float = 1.0):
        self.size = size
        self.loop = loop
        width, height = size
        sky = paint(theme, spec.get("sky", "field"))
        deep = paint(theme, spec.get("deep", "navy"))
        # Layers run from "base" (the sky unless given) towards "deep".
        base = paint(theme, spec.get("base", spec.get("sky", "field")))
        self.back = Image.new("RGBA", size, sky + (255,))
        if "sky_top" in spec:
            # A soft fall from the top colour to the sky by "sky_to".
            top = paint(theme, spec["sky_top"])
            reach = max(1, round(height * spec.get("sky_to", 0.6)))
            band = Image.new("RGBA", (1, reach))
            for y in range(reach):
                f = (y / reach) ** 1.4
                band.putpixel((0, y), mix(top, sky, f) + (255,))
            self.back.paste(band.resize((width, reach)), (0, 0))
        draw = ImageDraw.Draw(self.back)

        rng = random.Random(spec.get("seed", 7))
        for _ in range(spec.get("stars", 0)):
            sx, sy = rng.uniform(0, width), rng.uniform(0, height * spec.get("stars_to", 0.5))
            r = rng.choice((2, 2, 3, 4)) * height / 1646
            draw.ellipse((sx - r, sy - r, sx + r, sy + r), fill=mix(sky, (255, 255, 255), rng.uniform(0.5, 0.9)) + (255,))

        if spec.get("rays"):
            # Light from the surface, flat bands that narrow as they fall.
            rays = Image.new("RGBA", size, (0, 0, 0, 0))
            rd = ImageDraw.Draw(rays)
            for i in range(spec["rays"]):
                x = width * (i + 0.5 + rng.uniform(-0.25, 0.25)) / spec["rays"]
                top_w = width * rng.uniform(0.05, 0.1)
                fall = height * rng.uniform(0.55, 0.85)
                slant = width * 0.08
                rd.polygon([(x - top_w / 2, 0), (x + top_w / 2, 0), (x + slant + top_w * 0.1, fall), (x + slant - top_w * 0.1, fall)],
                           fill=(255, 255, 255, 30))
            self.back.alpha_composite(rays)

        if "sun" in spec:
            sun = spec["sun"]
            cx, cy = sun["at"][0] * width, sun["at"][1] * height
            r = sun["r"] * height
            color = paint(theme, sun.get("color", "sun"))
            if sun.get("ring", True):
                ring = r * 1.45
                draw.ellipse((cx - ring, cy - ring, cx + ring, cy + ring), fill=mix(sky, color, 0.35) + (255,))
            draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color + (255,))

        self.layers = []
        for i, layer in enumerate(spec.get("layers", [])):
            kind = layer["kind"]
            color = paint(theme, layer["color"]) if "color" in layer else mix(base, deep, layer.get("shade", 0.3))
            period = min(layer.get("period", 1280), width * 2)
            seed = layer.get("seed", 11 + i)
            if kind in ("hills", "water"):
                harmonics = layer.get("harmonics") or ([(1, 1.0), (2, 0.5), (3, 0.25)] if kind == "hills" else [(2, 1.0), (3, 0.45), (5, 0.2)])
                heights = profile(period, layer.get("amp", 0.02) * height, harmonics, seed)
                ripple_color = mix(color, sky, layer.get("ripples", {}).get("light", 0.3))
                strip = filled(period, height, layer["y"] * height, heights, color,
                               layer.get("ripples"), ripple_color, seed)
            elif kind == "pines":
                strip = pines(period, height, layer["y"] * height, layer.get("amp", 0.02) * height,
                              layer.get("height", 0.12) * height, color, seed, layer.get("density", 1.0),
                              layer.get("group", 5))
            elif kind == "boat":
                strip = boat(period, height, layer["y"] * height, layer.get("size", 100), layer.get("at", 0.5), color,
                             layer.get("sunk", 40))
            elif kind == "reeds":
                strip = reeds(period, height, layer["y"] * height, layer.get("height", 0.12) * height, color, seed,
                              layer.get("density", 1.0), layer.get("cattails", 0.3))
            elif kind == "school":
                strip = school(period, height, layer["y"] * height, layer.get("size", 0.05) * height,
                               layer.get("count", 5), color, seed, layer.get("facing", 1))
            elif kind == "bubbles":
                strip = bubbles(period, height, layer["y"] * height, layer.get("count", 12),
                                layer.get("size", 0.012) * height, color, seed)
            else:
                raise ValueError(f"unknown scene layer {kind}")
            self.layers.append((layer, period, self.tile(strip, period, kind == "bubbles")))

    def tile(self, strip: Image.Image, period: int, both: bool) -> Image.Image:
        """The strip repeated to the canvas width plus one period (and
        height too, for layers that rise), so a frame is a crop."""
        width, height = self.size
        out = Image.new("RGBA", (width + period, height + (period if both else 0)), (0, 0, 0, 0))
        for x in range(0, out.width, period):
            for y in range(0, out.height, period) if both else (0,):
                out.alpha_composite(strip, (x, y))
        return out

    def frame(self, t: float = 0.0) -> Image.Image:
        width, height = self.size
        img = self.back.copy()
        phase = (t / self.loop) % 1.0
        for layer, period, tiled in self.layers:
            shift = round(phase * layer.get("speed", 1) * period) % period
            if layer["kind"] == "bubbles":
                # Bubbles rise; "speed" sideways drift, "rise" periods upward.
                lift = round(phase * layer.get("rise", 1) * period) % period
                piece = tiled.crop((shift, lift, shift + width, lift + height))
                top = round(layer["y"] * height)
                mask = Image.new("L", (width, height), 0)
                mask.paste(255, (0, top, width, height))
                piece.putalpha(Image.composite(piece.getchannel("A"), mask, mask))
                img.alpha_composite(piece)
                continue
            img.alpha_composite(tiled.crop((shift, 0, shift + width, height)))
        return img
