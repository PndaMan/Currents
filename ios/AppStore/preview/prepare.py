# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10.4"]
# ///
"""Gather what the preview composition reads into public/.

The app shots are animated from full-size captures (1320x2868): the store
stills, plus a few frames taken from the recorded takes where no still shows
that moment. Each animated screen also gets a plate, its background with the
content lifted off (the empty left margin stretched across), so rows can
rise onto it one at a time.

    uv run prepare.py [--stills DIR] [--footage DIR]
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PUBLIC = HERE / "public"

sys.path.insert(0, str(ROOT / "scripts"))
from store_art import phone  # noqa: E402  the same iPhone the screenshots draw

STILLS = [
    "today", "add-menu", "log-catch-camera", "log-catch-id-trout", "forecast-week", "forecast-day",
    "forecast-day-hour", "explore", "explore-near", "streak-moment",
]
# Moments only the takes show: (name, take, seconds in).
FRAMES = [
    ("today-65", "add-flow-light", 21.0),      # Today just before the Add tab is pressed
    ("id-scan", "add-flow-light", 41.63),      # identifying, between passes of the scan line
]
# Plates: (still, x of an empty column of background).
PLATES = [("today", 14), ("forecast-week", 14), ("forecast-day", 14), ("streak-moment", 14)]
# Stills shown inside a phone on the opening frame: (still, boxes to paint out).
PHONES = [("today", []), ("log-catch-id-trout", [(645, 1515, 729, 1578)])]  # the species picker's chevron


def frame(take: Path, seconds: float, out: Path) -> None:
    # What was on screen at that time: the last frame written at or before
    # it. The recorder writes frames only on change, so a seek or the first
    # frame after the time can show a later moment.
    times = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "frame=pts_time",
                            "-of", "csv=p=0", str(take)], check=True, capture_output=True, text=True).stdout
    shown = max(t for t in (float(v.strip(",")) for v in times.split()) if t <= seconds)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(take), "-vf", f"select='gte(t,{shown - 0.0005})'",
                    "-frames:v", "1", str(out)], check=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--stills", type=Path, default=ROOT / "ios/build/store-stills")
    ap.add_argument("--footage", type=Path, default=ROOT / "ios/build/preview-footage")
    args = ap.parse_args()

    for d in ("s", "p", "phones", "fonts"):
        (PUBLIC / d).mkdir(parents=True, exist_ok=True)
    for name in STILLS:
        shutil.copyfile(args.stills / f"{name}.png", PUBLIC / "s" / f"{name}.png")
    for name, take, seconds in FRAMES:
        out = PUBLIC / "s" / f"{name}.png"
        frame(args.footage / f"{take}.mp4", seconds, out)
        Image.open(out).convert("RGB").save(out)

    for name, x in PLATES:
        img = Image.open(PUBLIC / "s" / f"{name}.png").convert("RGB")
        img.crop((x, 0, x + 1, img.height)).resize(img.size).save(PUBLIC / "p" / f"{name}.png")

    for name, erase in PHONES:
        shot = Image.open(PUBLIC / "s" / f"{name}.png").convert("RGB")
        for box in erase:
            ImageDraw.Draw(shot).rectangle(box, fill=shot.getpixel((box[0] - 6, box[1])))
        phone(shot, "dark").save(PUBLIC / "phones" / f"{name}.png")

    # The streak card with its week dots taken off, for the dots to pop onto.
    card = Image.open(PUBLIC / "s" / "streak-moment.png").convert("RGB")
    ImageDraw.Draw(card).rectangle((110, 1812, 1210, 1936), fill=card.getpixel((660, 1800)))
    card.save(PUBLIC / "s" / "streak-empty.png")

    for f in (ROOT / "ios/AppStore/fonts").glob("InterDisplay-*.ttf"):
        shutil.copyfile(f, PUBLIC / "fonts" / f.name)
    shutil.copyfile(ROOT / "ios/Currents/Resources/Assets.xcassets/Logo.imageset/Logo@3x.png", PUBLIC / "logo.png")
    print(f"prepared {PUBLIC}")


if __name__ == "__main__":
    main()
