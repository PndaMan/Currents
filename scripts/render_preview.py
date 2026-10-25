# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10.4"]
# ///
"""Cut the App Store preview video from the recorded footage.

Reads ios/AppStore/preview.json and the clips that preview-footage.yml
records (1320x2868 MP4s named after the take). The edit alternates two kinds
of scene: a title card over one of the store art's lake scenes, drifting,
where the headline rises in line by line and one of the app's own fish or
lure drawings acts it out on the water, and a stretch of real footage, full
bleed, with slow pushes onto what matters and a ring where a finger taps.

    uv run scripts/render_preview.py --footage preview-footage --out build/preview.mp4

Writes 886x1920 H.264 (High, level 4.0) at 30 fps and about 11 Mbps with a
silent stereo AAC track, the format App Store Connect takes for a 6.9-inch
app preview. --sheet writes contact sheets of every sixth frame, for
checking the motion. Needs ffmpeg on the PATH.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scenes  # noqa: E402
from store_art import ROOT, artwork, color, draw_text, font, logo, place, rounded_mask, text_width  # noqa: E402

W, H = 886, 1920
FPS = 30
SRC_W, SRC_H = 1320, 2868   # the 6.9-inch simulator
POINT = 3                   # pixels per point on that screen


# MARK: - Timing


def clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def progress(t: float, start: float, length: float) -> float:
    return clamp((t - start) / length)


def lerp(a: float, b: float, x: float) -> float:
    return a + (b - a) * x


def ease_out(x: float) -> float:
    return 1 - (1 - x) ** 3


def ease_in(x: float) -> float:
    return x ** 3


def ease_in_out(x: float) -> float:
    return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def ease_back(x: float, s: float = 1.6) -> float:
    """Overshoots a little and settles, like a spring."""
    x -= 1
    return 1 + (s + 1) * x ** 3 + s * x ** 2


def ease_bounce(x: float) -> float:
    n, d = 7.5625, 2.75
    if x < 1 / d:
        return n * x * x
    if x < 2 / d:
        x -= 1.5 / d
        return n * x * x + 0.75
    if x < 2.5 / d:
        x -= 2.25 / d
        return n * x * x + 0.9375
    x -= 2.625 / d
    return n * x * x + 0.984375


# MARK: - Drawing


_sprites: dict = {}


def sprite(key, make):
    """Drawings are made once and reused on every frame."""
    if key not in _sprites:
        _sprites[key] = make()
    return _sprites[key]


def art(name: str, width: int, flip: bool = False) -> Image.Image:
    return sprite(("art", name, width, flip), lambda: artwork(name, width, flip))


def put(canvas: Image.Image, img: Image.Image, center, angle: float = 0, scale: float = 1, alpha: float = 1) -> None:
    """`img` centred on `center`, scaled, turned clockwise and faded."""
    if alpha <= 0 or scale <= 0:
        return
    if scale != 1:
        img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.BICUBIC)
    if alpha < 1:
        img = img.copy()
        img.putalpha(img.getchannel("A").point(lambda v: round(v * alpha)))
    place(canvas, img, center, angle)


def smooth(size: tuple[int, int], draw, scale: int = 4) -> Image.Image:
    """An anti-aliased RGBA drawing: `draw(ImageDraw, scale)` paints it
    `scale` times larger and it is reduced."""
    big = Image.new("RGBA", (size[0] * scale, size[1] * scale), (0, 0, 0, 0))
    draw(ImageDraw.Draw(big), scale)
    return big.resize(size, Image.LANCZOS)


def point_on(img_size: tuple[int, int], fraction, center, angle: float = 0):
    """Where a point of a drawing (as a fraction of its size) lands once
    the drawing is centred on `center` and turned `angle` degrees clockwise."""
    dx = (fraction[0] - 0.5) * img_size[0]
    dy = (fraction[1] - 0.5) * img_size[1]
    a = math.radians(angle)
    return (center[0] + dx * math.cos(a) - dy * math.sin(a),
            center[1] + dx * math.sin(a) + dy * math.cos(a))


def header(ink) -> Image.Image:
    """The logo and the app's name, as it sits at the top of every card."""
    def make():
        mark = logo(64, ink)
        f = font("Bold", 54)
        w = mark.width + 18 + math.ceil(text_width("Currents", f, -0.02))
        img = Image.new("RGBA", (w, 80), (0, 0, 0, 0))
        img.alpha_composite(mark, (0, 8))
        draw_text(img, "Currents", f, (mark.width + 18, 6), ink, -0.02)
        return img
    return sprite(("header", ink), make)


# MARK: - Illustrations
#
# Each one draws a drawing's moment `t` seconds into its title card, in the
# lower half of the card, below the headline.


def bite(canvas: Image.Image, t: float, theme: dict) -> None:
    """A crankbait comes across on its line and a bass runs it down."""
    ink = color(theme, "ink")
    lure = art("lure_crankbait", 190, flip=True)
    bass = art("fish_1", 500, flip=True)
    take = 0.95
    y = 1330

    # The lure is reeled to the right, wobbling, until the bass has it.
    if t < take:
        lure_x = lerp(450, 540, t / take)
        wobble = 5 * math.sin(t * 2 * math.pi * 5)
    else:
        lure_x = 540 + 40 * ease_out(progress(t, take, 0.9))
        wobble = 0
    tail = point_on(lure.size, (0.06, 0.45), (lure_x, y), wobble)

    # The bass closes in from the left and speeds up into the take.
    if t < take:
        mouth_x = lerp(-60, tail[0] + 14, ease_in(progress(t, 0.0, take)))
    else:
        mouth_x = tail[0] + 14
    bass_center = (mouth_x - 0.47 * bass.width, y + 8)
    swim = 4 * math.sin(t * 2 * math.pi * 3) * (1 - progress(t, take, 0.6))

    nose = point_on(lure.size, (0.96, 0.62), (lure_x, y), wobble)
    line = smooth((W, H // 4), lambda d, s: d.line(
        [(nose[0] * s, (nose[1] - y + H // 8) * s), ((W + 20) * s, (nose[1] - y + H // 8 - 150) * s)],
        fill=ink + (255,), width=4 * s))
    canvas.alpha_composite(line, (0, round(y - H // 8)))
    put(canvas, lure, (lure_x, y), wobble)
    put(canvas, bass, bass_center, swim)

    # Strike lines fanning out round the lure, ahead of the bass, the way a
    # hit is drawn in a comic.
    k = progress(t, take, 0.5)
    if 0 < k < 1:
        grow, fade = ease_out(min(1, k * 2.5)), 1 - ease_in(k)
        hit = (lure_x + 6, y)

        def strike(d, s):
            for i in range(5):
                a = math.radians(-100 + i * 50)
                r0, r1 = 120, 120 + 46 * grow
                d.line([((160 + r0 * math.cos(a)) * s, (160 + r0 * math.sin(a)) * s),
                        ((160 + r1 * math.cos(a)) * s, (160 + r1 * math.sin(a)) * s)],
                       fill=ink + (round(255 * fade),), width=8 * s)
        canvas.alpha_composite(smooth((320, 320), strike), (round(hit[0] - 160), round(hit[1] - 160)))


def snap(canvas: Image.Image, t: float, theme: dict) -> None:
    """A trout drifts in, the viewfinder closes on it, the shutter flashes
    and a tick says it's been identified."""
    ink, white, sun = color(theme, "ink"), color(theme, "white"), color(theme, "sun")
    trout = art("fish_17", 560)
    center = (443, 1360)
    drift = 1 - ease_out(progress(t, 0, 1.1))
    put(canvas, trout, (center[0] + 70 * drift, center[1] + 10 * math.sin(t * 2 * math.pi / 1.6)),
        2 * math.sin(t * 2 * math.pi / 1.3))

    # Four corner brackets, drawn 1.4 times over size so they stay sharp
    # while they close in.
    bw, bh, arm, stroke = 700, 420, 96, 13

    def corners(d, s):
        k = 1.4 * s
        w, h, a, p = bw * k, bh * k, arm * k, stroke * k
        o = p
        for (x, y, sx, sy) in ((o, o, 1, 1), (w + o, o, -1, 1), (o, h + o, 1, -1), (w + o, h + o, -1, -1)):
            d.line([(x, y + sy * a), (x, y), (x + sx * a, y)], fill=white + (255,), width=round(p), joint="curve")
            for px, py in ((x, y + sy * a), (x + sx * a, y), (x, y)):
                d.ellipse((px - p / 2, py - p / 2, px + p / 2, py + p / 2), fill=white + (255,))
    frame = sprite("brackets", lambda: smooth((round((bw + 2 * stroke) * 1.4), round((bh + 2 * stroke) * 1.4)), corners, 3))
    b = progress(t, 0.4, 0.45)
    if b > 0:
        put(canvas, frame, center, scale=lerp(1.35, 1.0, ease_back(b, 1.2)) / 1.4, alpha=ease_out(min(1, b * 2.5)))

    # The tick, popping in on the top right corner.
    def tick(d, s):
        d.ellipse((0, 0, 120 * s, 120 * s), fill=sun + (255,))
        d.line([(34 * s, 62 * s), (53 * s, 81 * s), (88 * s, 42 * s)], fill=ink + (255,), width=13 * s, joint="curve")
        for px, py in ((34, 62), (88, 42)):
            d.ellipse(((px - 6.5) * s, (py - 6.5) * s, (px + 6.5) * s, (py + 6.5) * s), fill=ink + (255,))
    k = progress(t, 1.25, 0.4)
    if k > 0:
        put(canvas, sprite("tick", lambda: smooth((120, 120), tick)),
            (center[0] + bw / 2 - 6, center[1] - bh / 2 + 6), scale=ease_back(k, 2.2))

    # The shutter flash.
    f = progress(t, 1.02, 0.4)
    if 0 < f < 1:
        flash = Image.new("RGBA", canvas.size, white + (round(230 * (1 - f) ** 2),))
        canvas.alpha_composite(flash)


def plan(canvas: Image.Image, t: float, theme: dict) -> None:
    """The day's bite as bars rising from a baseline, the best hour in
    yellow, and a bass jumping it."""
    white, sun = color(theme, "white"), color(theme, "sun")
    heights = [170, 250, 340, 520, 320, 230, 150]
    bar, gap, base = 74, 30, 1660
    left = (W - len(heights) * bar - (len(heights) - 1) * gap) / 2
    for i, h in enumerate(heights):
        g = progress(t, 0.12 + i * 0.05, 0.5)
        if g <= 0:
            continue
        hh = max(bar, round(h * ease_back(g, 1.1)))
        fill = sun if i == 3 else white
        img = Image.new("RGBA", (bar, hh), fill + (255,))
        img.putalpha(rounded_mask((bar, hh), bar / 2))
        canvas.alpha_composite(img, (round(left + i * (bar + gap)), base - hh))

    u = progress(t, 0.7, 1.0)
    if 0 < u < 1:
        bass = art("fish_1", 280, flip=True)
        rise = 640
        x = lerp(-170, W + 170, u)
        y = base - 60 - rise * 4 * u * (1 - u)
        angle = math.degrees(math.atan2(-rise * 4 * (1 - 2 * u), W + 340))
        put(canvas, bass, (x, y), angle)


def explore(canvas: Image.Image, t: float, theme: dict) -> None:
    """A pin drops onto the water, rings spread from it, and a pike swims
    past underneath."""
    ink, white, sun = color(theme, "ink"), color(theme, "white"), color(theme, "sun")
    tip = (443, 1450)

    for i in range(3):
        r = progress(t, 0.45 + i * 0.2, 1.0)
        if 0 < r < 1:
            rx = lerp(70, 330, ease_out(r))
            ry = rx * 0.3
            a = round(255 * (1 - r))
            ring = smooth((round(rx * 2 + 16), round(ry * 2 + 16)), lambda d, s: d.ellipse(
                (8 * s, 8 * s, (rx * 2 + 8) * s, (ry * 2 + 8) * s), outline=white + (a,), width=7 * s), 2)
            put(canvas, ring, tip)

    pike = art("fish_11", 540)
    put(canvas, pike, (lerp(W + 300, -300, t / 1.9), 1720 + 8 * math.sin(t * 2 * math.pi)),
        3 * math.sin(t * 2 * math.pi * 2))

    def pin(d, s):
        r, cx, cy, depth = 95, 100, 100, 205
        phi = math.acos(r / depth)
        pts = [(cx + r * math.cos(math.pi / 2 + sgn * phi), cy + r * math.sin(math.pi / 2 + sgn * phi)) for sgn in (-1, 1)]
        d.polygon([(pts[0][0] * s, pts[0][1] * s), (cx * s, (cy + depth) * s), (pts[1][0] * s, pts[1][1] * s)], fill=sun + (255,))
        d.ellipse(((cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s), fill=sun + (255,))
        d.ellipse(((cx - 38) * s, (cy - 38) * s, (cx + 38) * s, (cy + 38) * s), fill=ink + (255,))
    marker = sprite("pin", lambda: smooth((200, 310), pin))
    # It falls a short way, below the headline, and bounces as it lands.
    p = progress(t, 0.15, 0.6)
    if p > 0:
        drop = ease_bounce(p)
        shadow = smooth((160, 40), lambda d, s: d.ellipse((0, 0, 160 * s, 40 * s), fill=ink + (60,)))
        put(canvas, shadow, (tip[0], tip[1] + 4), scale=lerp(0.4, 1, drop), alpha=drop)
        y = lerp(tip[1] - 340, tip[1], drop)
        put(canvas, marker, (tip[0], y - 305 + marker.height / 2), alpha=ease_out(min(1, p * 4)))


def finale(canvas: Image.Image, t: float, theme: dict) -> None:
    """The logo springs up, with rings spreading behind it."""
    white = color(theme, "white")
    center = (443, 1330)
    for i in range(2):
        r = progress(t, 0.2 + i * 0.3, 1.4)
        if 0 < r < 1:
            rad = lerp(170, 420, ease_out(r))
            a = round(200 * (1 - r))
            ring = smooth((round(rad * 2 + 16),) * 2, lambda d, s: d.ellipse(
                (8 * s, 8 * s, (rad * 2 + 8) * s, (rad * 2 + 8) * s), outline=white + (a,), width=8 * s), 2)
            put(canvas, ring, center)
    k = progress(t, 0.05, 0.55)
    if k > 0:
        put(canvas, sprite("big-logo", lambda: logo(400, white)), center, scale=ease_back(k, 1.8))


ILLUSTRATIONS = {"bite": bite, "snap": snap, "plan": plan, "explore": explore, "finale": finale}


# MARK: - Scenes


def backdrop(spec: dict, theme: dict, named: dict) -> scenes.Scene:
    """One of the store art's lake scenes (store-art.json "scenes"), drawn
    at the recording's size. "drop" lowers everything but the foreground so
    a three-line headline stays in the sky, "sun" moves the sun or moon
    clear of it, and "set" replaces any of the scene's own keys (a deeper
    sky behind white type, say)."""
    scene = copy.deepcopy(named[spec["name"]]) | spec.get("set", {})
    for layer in scene["layers"]:
        if layer.get("y", 1) < 0.9:
            layer["y"] += spec.get("drop", 0)
    if "sun" in spec and "sun" in scene:
        scene["sun"]["at"] = spec["sun"]
    return scenes.Scene(scene, theme, (SRC_W, SRC_H), spec.get("loop", 30))


class Title:
    """A lake scene (or the brand colour), the logo and name at the top,
    the headline rising in line by line, and an illustration acting it
    out."""

    LEFT = 64

    def __init__(self, spec: dict, theme: dict, named: dict):
        self.spec, self.theme = spec, theme
        self.scene = backdrop(spec["scene"], theme, named) if "scene" in spec else None
        self.duration = spec["duration"]
        self.frames_count = round(self.duration * FPS)
        self.field = color(theme, spec.get("field", "field"))
        self.ink = color(theme, spec.get("color", "ink"))
        size = spec.get("size", 118)
        while max(text_width(t, font("Bold", size), -0.025) for t in spec["lines"]) > W - 2 * self.LEFT:
            size -= 2
        f = font("Bold", size)
        self.leading = round(f.size * spec.get("leading", 1.02))
        self.top = spec.get("top", 330)
        self.lines = []
        for text in spec["lines"]:
            img = Image.new("RGBA", (math.ceil(text_width(text, f, -0.025)) + 12, self.leading + f.size // 3), (0, 0, 0, 0))
            draw_text(img, text, f, (0, 0), self.ink, -0.025)
            self.lines.append(img)
        self.illustration = ILLUSTRATIONS[spec["art"]] if spec.get("art") else None

    def frame(self, t: float) -> Image.Image:
        if self.scene:
            canvas = self.scene.frame(t).resize((W, H), Image.LANCZOS)
        else:
            canvas = Image.new("RGBA", (W, H), self.field + (255,))
        canvas.alpha_composite(header(self.ink), (self.LEFT, 118))
        for i, img in enumerate(self.lines):
            x = progress(t, 0.06 + i * 0.09, 0.42)
            if x <= 0:
                continue
            # Each line rises out of a slot at its own baseline.
            drop = round((1 - ease_out(x)) * img.height)
            if drop < img.height:
                canvas.alpha_composite(img.crop((0, 0, img.width, img.height - drop)),
                                       (self.LEFT, self.top + i * self.leading + drop))
        if self.illustration:
            self.illustration(canvas, t, self.theme)
        return canvas.convert("RGB")

    def frames(self):
        for i in range(self.frames_count):
            yield self.frame(i / FPS)


class Footage:
    """Parts of one recorded clip, played at their own speeds, framed by
    the zoom keyframes, with a ring drawn for each tap and any "cover"
    painted out."""

    def __init__(self, spec: dict, folder: Path):
        self.spec = spec
        self.path = folder / f"{spec['clip']}.mp4"
        if not self.path.exists():
            raise SystemExit(f"missing clip {self.path}")
        self.parts = []
        for part in spec["parts"]:
            if "hold" in part:
                n = round(part["hold"] * FPS)
            else:
                n = round((part["to"] - part["from"]) / part.get("speed", 1) * FPS)
            self.parts.append((part, n))
        self.frames_count = sum(n for _, n in self.parts)
        self.duration = self.frames_count / FPS
        self.zoom = spec.get("zoom") or [{"t": 0, "center": [220, 478], "scale": 1}]
        self.taps = spec.get("taps", [])
        self.covers = spec.get("cover", [])

    def decode(self, start: float, length: float, speed: float, n: int):
        # The recorder writes a frame only when the screen changes, so what
        # is on screen at a time is the last frame written before it. A seek
        # lands on the next one instead, which can be seconds later; so the
        # clip is read from the top, its gaps filled at a steady rate, and
        # then cut.
        vf = (f"fps={FPS}:round=down,trim=start={start:.3f}:duration={length + 0.5:.3f},"
              f"setpts=(PTS-STARTPTS)/{speed},fps={FPS},scale={SRC_W}:{SRC_H}:flags=lanczos")
        cmd = ["ffmpeg", "-v", "error", "-i", str(self.path), "-vf", vf,
               "-frames:v", str(n), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
        size, last, count = SRC_W * SRC_H * 3, None, 0
        while count < n:
            buf = proc.stdout.read(size)
            if len(buf) < size:
                break
            last = Image.frombytes("RGB", (SRC_W, SRC_H), buf)
            count += 1
            yield last
        proc.stdout.close()
        proc.wait()
        if last is None:
            raise SystemExit(f"{self.path.name}: no frames at {start:.2f}s")
        if count < n:
            print(f"  {self.path.name}: clip ends {n - count} frames early at {start + length:.2f}s; holding")
        for _ in range(n - count):
            yield last

    def view(self, t: float):
        """The crop of the source frame at scene time `t`."""
        keys = self.zoom
        if t <= keys[0]["t"]:
            a = b = keys[0]
            x = 0
        elif t >= keys[-1]["t"]:
            a = b = keys[-1]
            x = 0
        else:
            i = next(i for i in range(1, len(keys)) if keys[i]["t"] >= t)
            a, b = keys[i - 1], keys[i]
            x = ease_in_out((t - a["t"]) / (b["t"] - a["t"]))
        scale = lerp(a["scale"], b["scale"], x)
        cx = lerp(a["center"][0], b["center"][0], x) * POINT
        cy = lerp(a["center"][1], b["center"][1], x) * POINT
        cw = SRC_W / scale
        ch = cw * H / W
        x0 = clamp(cx - cw / 2, 0, SRC_W - cw)
        y0 = clamp(cy - ch / 2, 0, SRC_H - ch)
        return (x0, y0, x0 + cw, y0 + ch)

    def ring(self, frame: Image.Image, t: float, box) -> None:
        """A touch: a soft disc that presses in and a ring that spreads."""
        for tap in self.taps:
            k = progress(t, tap["t"] - 0.15, 0.65)
            if not 0 < k < 1:
                continue
            sx = W / (box[2] - box[0])
            x = (tap["at"][0] * POINT - box[0]) * sx
            y = (tap["at"][1] * POINT - box[1]) * sx
            press = ease_out(min(1, k * 4))
            fade = 1 - ease_in(progress(k, 0.35, 0.65))
            spread = ease_out(progress(k, 0.2, 0.8))

            def draw(d, s):
                c = 110 * s
                r = 36 * press * s
                d.ellipse((c - r, c - r, c + r, c + r), fill=(6, 18, 31, round(70 * fade)),
                          outline=(255, 255, 255, round(235 * fade)), width=4 * s)
                rr = (40 + 60 * spread) * s
                d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=(255, 255, 255, round(170 * (1 - spread))), width=4 * s)
            layer = smooth((220, 220), draw, 3)
            overlay = Image.new("RGBA", frame.size, (0, 0, 0, 0))
            overlay.alpha_composite(layer, (round(x - 110), round(y - 110)))
            frame.paste(Image.alpha_composite(frame.convert("RGBA"), overlay).convert("RGB"))

    def cover(self, img: Image.Image, t: float) -> None:
        """Paints out each "box" (in points) from scene time "from", row by
        row in the colour just right of it, so a soft fall in the
        background carries on through."""
        draw = None
        for c in self.covers:
            if t < c["from"]:
                continue
            draw = draw or ImageDraw.Draw(img)
            x, y, w, h = (v * POINT for v in c["box"])
            for row in range(round(y), round(y + h)):
                draw.line([(x, row), (x + w, row)], fill=img.getpixel((round(x + w + 6), row)))

    def frames(self):
        i = 0
        for part, n in self.parts:
            if "hold" in part:
                source = self.decode(part["at"], 0.2, 1, 1)
                still = next(source)
                source = (still for _ in range(n))
            else:
                speed = part.get("speed", 1)
                source = self.decode(part["from"], part["to"] - part["from"], speed, n)
            for img in source:
                t = i / FPS
                if self.covers:
                    self.cover(img, t)
                box = self.view(t)
                frame = img.resize((W, H), Image.LANCZOS, box=box)
                if self.taps:
                    self.ring(frame, t, box)
                yield frame
                i += 1


def slide(previous: Image.Image, frame: Image.Image, k: float) -> Image.Image:
    """The new scene rides up over the last frame of the old one, its top
    corners rounded like a sheet until it lands."""
    e = ease_in_out(k)
    top = round(H * (1 - e))
    radius = lerp(64, 0, e)
    out = previous.copy()
    if top < H:
        part = frame.crop((0, 0, W, H - top))
        if radius > 1:
            mask = Image.new("L", part.size, 255)
            corner = rounded_mask((round(radius * 2), round(radius * 2)), radius)
            mask.paste(corner.crop((0, 0, round(radius), round(radius))), (0, 0))
            mask.paste(corner.crop((round(radius), 0, round(radius * 2), round(radius))), (W - round(radius), 0))
            out.paste(part, (0, top), mask)
        else:
            out.paste(part, (0, top))
    return out


# MARK: - Output


def contact_sheets(frames: list[tuple[float, Image.Image]], folder: Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    tw, th, cols, rows = 177, 384, 10, 4
    f = font("Bold", 20)
    per = cols * rows
    for page in range(math.ceil(len(frames) / per)):
        sheet = Image.new("RGB", (cols * (tw + 8) + 8, rows * (th + 36) + 8), (40, 40, 40))
        d = ImageDraw.Draw(sheet)
        for j, (t, img) in enumerate(frames[page * per:(page + 1) * per]):
            x, y = 8 + (j % cols) * (tw + 8), 8 + (j // cols) * (th + 36)
            sheet.paste(img, (x, y + 28))
            d.text((x, y), f"{t:05.2f}s", font=f, fill=(255, 255, 255))
        sheet.save(folder / f"sheet-{page + 1:02d}.png")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--footage", type=Path, required=True, help="folder of <clip>.mp4 takes")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--config", type=Path, default=ROOT / "ios/AppStore/preview.json")
    ap.add_argument("--scenes", help="render only these scenes, by number from 1 (\"3,4\")")
    ap.add_argument("--sheet", type=Path, help="folder for contact sheets of every sixth frame")
    args = ap.parse_args()

    config = json.loads(args.config.read_text())
    art = json.loads((ROOT / "ios/AppStore/store-art.json").read_text())
    theme = art["theme"] | config.get("theme", {})
    specs = config["scenes"]
    if args.scenes:
        keep = {int(s) for s in args.scenes.split(",")}
        specs = [s for i, s in enumerate(specs, 1) if i in keep]
    parts = [Title(s, theme, art.get("scenes", {})) if s["type"] == "title" else Footage(s, args.footage) for s in specs]
    total = sum(s.frames_count for s in parts)
    print(f"{len(parts)} scenes, {total / FPS:.2f}s")
    if not args.scenes and not 15 <= total / FPS <= 30:
        raise SystemExit("App Store previews run 15 to 30 seconds")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    encoder = subprocess.Popen([
        "ffmpeg", "-v", "error", "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-f", "lavfi", "-t", f"{total / FPS:.3f}", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
        "-map", "0:v", "-map", "1:a",
        "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p",
        "-preset", "slow", "-b:v", "11M", "-maxrate", "12M", "-bufsize", "16M",
        "-r", str(FPS), "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
        "-movflags", "+faststart", str(args.out),
    ], stdin=subprocess.PIPE)

    sheet: list[tuple[float, Image.Image]] = []
    previous = None
    n = 0
    for number, (spec, scene) in enumerate(zip(specs, parts), 1):
        print(f"scene {number}: {spec.get('clip') or ' / '.join(spec['lines'])} ({scene.duration:.2f}s)")
        transition = spec.get("in", "cut")
        for i, frame in enumerate(scene.frames()):
            if transition == "slide" and previous is not None and i < 0.45 * FPS:
                frame = slide(previous, frame, i / (0.45 * FPS))
            encoder.stdin.write(frame.tobytes())
            if args.sheet and n % 6 == 0:
                sheet.append((n / FPS, frame.resize((177, 384), Image.LANCZOS)))
            n += 1
            last = frame
        previous = last
    encoder.stdin.close()
    if encoder.wait() != 0:
        raise SystemExit("ffmpeg failed")
    print(f"wrote {args.out} ({n} frames, {n / FPS:.2f}s)")
    if args.sheet:
        contact_sheets(sheet, args.sheet)
        print(f"wrote sheets to {args.sheet}")


if __name__ == "__main__":
    main()
