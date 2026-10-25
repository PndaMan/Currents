# /// script
# requires-python = ">=3.11"
# dependencies = ["librosa>=0.11", "soundfile>=0.12"]
# ///
"""Find the beats of the preview's music, so the cuts can land on them.

Prints JSON: {"bpm": 136.0, "beats": [0.19, 0.63, ...]} with each beat's
time in seconds over the first `--seconds` of the track.

    uv run beats.py music.mp3 [--seconds 32]
"""

from __future__ import annotations

import argparse
import json

import librosa
import numpy as np


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("music")
    ap.add_argument("--seconds", type=float, default=32)
    args = ap.parse_args()

    y, sr = librosa.load(args.music, sr=22050, mono=True, duration=args.seconds + 2)
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr, units="time")
    beats = [round(float(t), 3) for t in beats if t <= args.seconds]
    print(json.dumps({"bpm": round(float(np.atleast_1d(tempo)[0]), 1), "beats": beats}))


if __name__ == "__main__":
    main()
