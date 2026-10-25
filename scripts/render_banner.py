# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10.4"]
# ///
"""Render the product page header as a slow looping video.

The "banner" entry in ios/AppStore/store-art.json is a layered scene
(scripts/scenes.py) with the Currents mark and name over it. Each layer
drifts sideways at its own speed, far ones slowest, and every layer moves a
whole number of its own repeats over the loop, so the video loops without a
jump.

    uv run scripts/render_banner.py
    uv run scripts/render_banner.py --sheet /path/to/sheet.png

Writes ios/build/appstore-media/creative/header.mp4 (3840x1646, H.264, no
sound, as the Header video slot takes) and header-poster.png beside it, the
first frame, which is also the still shown before the video plays. --sheet
writes four frames across the loop instead, to check the layout quickly.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scenes  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "ios/AppStore/store-art.json"
FONTS = ROOT / "ios/AppStore/fonts"
OUT = ROOT / "ios/build/appstore-media/creative/header.mp4"


def lockup(spec: dict, theme: dict, size: tuple[int, int]) -> Image.Image:
    """The mark above the name, centred on `center`, on a clear canvas."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    color = scenes.paint(theme, spec.get("color", "white"))
    f = ImageFont.truetype(str(FONTS / f"InterDisplay-{spec.get('weight', 'Bold')}.ttf"), spec["size"])
    text = spec["text"]
    tracking = spec.get("tracking", 0) * spec["size"]
    width = f.getlength(text) + tracking * (len(text) - 1)
    # Cap height, measured, so the pair is centred on what is drawn.
    top, bottom = f.getbbox("C", anchor="ls")[1], 0
    cap = bottom - top

    mark = scenes.tint(scenes.mark(spec["mark"]), color)
    total = mark.height + spec["gap"] + cap
    cx, cy = spec["center"]
    y = cy - total / 2
    img.alpha_composite(mark, (round(cx - mark.width / 2 + spec.get("mark_nudge", 0)), round(y)))
    baseline = y + mark.height + spec["gap"] + cap
    draw = ImageDraw.Draw(img)
    x = cx - width / 2
    for i, ch in enumerate(text):
        draw.text((x + f.getlength(text[:i]) + tracking * i, baseline), ch, font=f, fill=color + (255,), anchor="ls")
    return img


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--sheet", type=Path, help="write four frames across the loop to this PNG and stop")
    args = parser.parse_args()

    config = json.loads(args.config.read_text())
    theme, spec = config["theme"], config["banner"]
    size = tuple(spec["size"])
    loop, fps = spec["loop"], spec["fps"]
    scene = scenes.Scene(spec["scene"], theme, size, loop)
    over = lockup(spec["lockup"], theme, size)

    def frame(t: float) -> Image.Image:
        img = scene.frame(t)
        img.alpha_composite(over)
        return img.convert("RGB")

    if args.sheet:
        width = size[0] // 2
        frames = [frame(loop * i / 4).resize((width, size[1] // 2), Image.LANCZOS) for i in range(4)]
        sheet = Image.new("RGB", (width, frames[0].height * 4 + 12 * 3), (255, 255, 255))
        for i, f in enumerate(frames):
            sheet.paste(f, (0, i * (f.height + 12)))
        args.sheet.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(args.sheet)
        print(f"wrote {args.sheet}")
        return

    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg is needed to write the video")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    poster = args.out.with_name(args.out.stem + "-poster.png")
    frame(0).save(poster, optimize=True)

    encode = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{size[0]}x{size[1]}",
         "-r", str(fps), "-i", "-", "-c:v", "libx264", "-profile:v", "high", "-preset", "slow", "-crf", "16",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", str(args.out)],
        stdin=subprocess.PIPE)
    count = round(loop * fps)
    for i in range(count):
        encode.stdin.write(frame(i / fps).tobytes())
        if i % fps == 0:
            print(f"\r{i // fps}/{loop} s", end="", flush=True)
    encode.stdin.close()
    if encode.wait() != 0:
        sys.exit("ffmpeg failed")
    print(f"\rwrote {args.out.relative_to(ROOT)} and {poster.name}")


if __name__ == "__main__":
    main()
