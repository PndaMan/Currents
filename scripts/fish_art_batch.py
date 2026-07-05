#!/usr/bin/env python3
"""
Generate the full fish-illustration set via the Gemini **Batch API** — same
Nano Banana (gemini-2.5-flash-image) model as the live path, at a flat 50%
discount ($0.0195/image vs $0.039), processed within a 24h window. This is how
we cover all ~1500 species at top quality while staying under budget.

Two phases (run as separate CI steps; the job persists on Google's side):

    python scripts/fish_art_batch.py submit          # queue all missing
    python scripts/fish_art_batch.py submit --force   # queue ALL (uniform set)
    python scripts/fish_art_batch.py submit --ids 1,301   # tiny test batch
    python scripts/fish_art_batch.py collect          # poll; write art when done

`submit` uploads one JSONL request file (each line redraws a species' real photo
into a flat facing-left illustration) and records the batch job name in
.fish_batch/job.json. `collect` polls that job; once it SUCCEEDS it downloads the
results, post-processes each image (white→transparent, force facing-left, resize)
and writes the imagesets. Re-running `collect` before completion just reports the
state and exits — so a daily/hourly CI re-run drives it to done.

Results persist on Google's side, so re-running `collect` never re-charges — only
`submit` costs money.

Env: GEMINI_API_KEY (paid tier required for batch).
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import time
from io import BytesIO
from pathlib import Path

import numpy as np
import requests
from concurrent.futures import ThreadPoolExecutor
from google import genai
from google.genai import types
from PIL import Image
from scipy import ndimage

# Reuse the exact post-processing + reference logic from the live pipeline so the
# batch set is stylistically identical to the samples already approved.
from generate_fish_art import (
    ASSET_DIR,
    INSTRUCTION,
    SEED_JSON,
    facing_right,
    fetch_ref_bytes,
    has_png,
    ref_url,
    write_imageset,
)

WORK_PX = 512   # downscale the 1024px render to here before keying (much faster)
WORKERS = 12    # parallel facing-checks (I/O-bound Gemini-flash calls)


def key_white(img: Image.Image) -> Image.Image:
    """Flood the near-white background to transparent — vectorised (numpy+scipy),
    ~100x faster than the pure-Python BFS. Labels near-white regions and drops
    only the ones connected to the image border (the background, not white
    bellies/spots enclosed by the fish outline)."""
    img = img.convert("RGBA")
    arr = np.array(img)
    near_white = np.all(arr[..., :3] > 230, axis=-1)
    lbl, _ = ndimage.label(near_white)
    border = np.unique(np.concatenate([lbl[0, :], lbl[-1, :], lbl[:, 0], lbl[:, -1]]))
    border = border[border != 0]
    if border.size:
        arr[..., 3][np.isin(lbl, border)] = 0
    return Image.fromarray(arr, "RGBA")


def is_low_quality(img: Image.Image) -> bool:
    """Reject near-black or near-greyscale renders (the 'dark crappie' failure)."""
    small = img.convert("RGBA").resize((48, 48))
    a = np.asarray(small.getchannel("A"))
    rgb = np.asarray(small.convert("RGB")).astype(np.int16)
    m = a > 25
    if m.sum() < 60:
        return True
    px = rgb[m]
    lum = px.mean(axis=1).mean()
    sat = (px.max(axis=1) - px.min(axis=1)).mean()
    return lum < 48 or sat < 12

MODEL = os.environ.get("GEMINI_MODEL") or "gemini-2.5-flash-image"
OUT_PX = 320  # crisp on retina grids; generation cost is independent of this
STATE_DIR = Path(__file__).resolve().parents[1] / ".fish_batch"
JOB_FILE = STATE_DIR / "job.json"
REQ_FILE = STATE_DIR / "requests.jsonl"

DONE_STATES = {
    "JOB_STATE_SUCCEEDED",
    "JOB_STATE_FAILED",
    "JOB_STATE_CANCELLED",
    "JOB_STATE_EXPIRED",
}


def client() -> genai.Client:
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not key:
        raise SystemExit("GEMINI_API_KEY is not set (paid tier required for batch).")
    return genai.Client(api_key=key)


def select(species: list[dict], force: bool, ids: str) -> list[dict]:
    if ids:
        want = {int(x) for x in ids.split(",") if x.strip()}
        return [s for s in species if int(s["id"]) in want]
    return [s for s in species if force or not has_png(int(s["id"]))]


def build_request_line(sp: dict) -> dict:
    raw, mime = fetch_ref_bytes(ref_url(sp))
    b64 = base64.b64encode(raw).decode()
    return {
        "key": str(int(sp["id"])),
        "request": {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {"text": INSTRUCTION},
                        {"inlineData": {"mimeType": mime, "data": b64}},
                    ],
                }
            ],
            "generationConfig": {"responseModalities": ["IMAGE"]},
        },
    }


def submit(force: bool, ids: str) -> None:
    species = json.loads(SEED_JSON.read_text())
    todo = select(species, force, ids)
    print(f"{len(species)} species; {len(todo)} to queue for batch.")
    if not todo:
        print("Nothing to queue.")
        return

    STATE_DIR.mkdir(exist_ok=True)
    n = 0
    with REQ_FILE.open("w") as f:
        for i, sp in enumerate(todo, start=1):
            try:
                line = build_request_line(sp)
            except Exception as e:  # noqa: BLE001
                print(f"  skip fish_{sp['id']}: ref fetch failed ({e})")
                continue
            f.write(json.dumps(line) + "\n")
            n += 1
            if i % 100 == 0:
                print(f"  prepared {i}/{len(todo)} requests")
            time.sleep(0.1)  # be polite to iNaturalist
    print(f"Wrote {n} requests to {REQ_FILE} ({REQ_FILE.stat().st_size/1e6:.1f} MB).")

    c = client()
    up = c.files.upload(
        file=str(REQ_FILE),
        config=types.UploadFileConfig(display_name="fish-art-batch", mime_type="jsonl"),
    )
    print(f"Uploaded input file: {up.name}")
    job = c.batches.create(model=MODEL, src=up.name)
    print(f"Created batch job: {job.name} (state {job.state})")
    JOB_FILE.write_text(json.dumps({"job": job.name, "input": up.name, "n": n}, indent=2))
    print(f"Saved {JOB_FILE}. Run `collect` (repeatedly) until it succeeds.")


def _state_name(state) -> str:
    return getattr(state, "name", str(state))


def _extract_image(response: dict) -> Image.Image | None:
    for cand in (response or {}).get("candidates", []):
        content = cand.get("content") or {}
        for part in content.get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                blob = base64.b64decode(inline["data"])
                return Image.open(BytesIO(blob)).convert("RGB")
    return None


def faces_right_llm(img: Image.Image, c: genai.Client) -> bool | None:
    """Ask a cheap vision model which way the fish's head points. Far more
    reliable than a geometric heuristic across 1500 diverse body shapes.
    Returns True (right, needs flip), False (left), or None if the call fails."""
    buf = BytesIO()
    img.convert("RGB").save(buf, "PNG")
    try:
        resp = c.models.generate_content(
            model="gemini-2.5-flash",
            contents=[
                types.Part(
                    text="This is a single cartoon fish on a white background. "
                    "Which way does the fish's HEAD point — LEFT or RIGHT? "
                    "Answer with exactly one word: LEFT or RIGHT."
                ),
                types.Part(inline_data=types.Blob(mime_type="image/png", data=buf.getvalue())),
            ],
        )
        t = (resp.text or "").strip().upper()
    except Exception as e:  # noqa: BLE001
        print(f"    (orientation check failed: {e})")
        return None
    if t.startswith("RIGHT"):
        return True
    if t.startswith("LEFT"):
        return False
    return None


def _fit_square(img: Image.Image, px: int) -> Image.Image:
    """Scale the fish to fit, preserving aspect, centered on a transparent square
    — so elongated/round species are never squashed into a square."""
    img = img.convert("RGBA")
    bbox = img.getchannel("A").getbbox()
    if bbox:
        img = img.crop(bbox)
    img.thumbnail((px, px), Image.LANCZOS)
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    canvas.paste(img, ((px - img.width) // 2, (px - img.height) // 2), img)
    return canvas


def _process(sid: int, raw: Image.Image, c: genai.Client) -> bool:
    """Full post-processing for one species: orientation (LLM) + key + flip + fit.
    Runs inside a thread pool; only the disk write happens back on the main thread."""
    work = raw.copy()
    work.thumbnail((WORK_PX, WORK_PX), Image.LANCZOS)  # key on a smaller image → fast
    keyed = key_white(work)
    if is_low_quality(keyed):
        return False
    right = faces_right_llm(raw, c)
    if right is None:  # LLM unavailable — fall back to the geometric guess
        right = facing_right(keyed)
    if right:
        keyed = keyed.transpose(Image.FLIP_LEFT_RIGHT)  # uniform: all face left
    write_imageset(sid, _fit_square(keyed, OUT_PX))
    return True


def collect() -> None:
    if not JOB_FILE.exists():
        raise SystemExit("No .fish_batch/job.json — run `submit` first.")
    meta = json.loads(JOB_FILE.read_text())
    c = client()
    job = c.batches.get(name=meta["job"])
    state = _state_name(job.state)
    print(f"Batch {meta['job']}: {state}")
    if state not in DONE_STATES:
        print("Still processing — re-run `collect` later.")
        return
    if state != "JOB_STATE_SUCCEEDED":
        raise SystemExit(f"Batch ended in {state}; inspect the job on Google's side.")

    # 1. Gather all (sid, image) pairs from the batch results.
    items: list[tuple[int, Image.Image]] = []
    dest = job.dest

    def add(key, response) -> None:
        try:
            sid = int(key)
        except (TypeError, ValueError):
            return
        img = _extract_image(response)
        if img is not None:
            items.append((sid, img))

    if getattr(dest, "inlined_responses", None):
        for item in dest.inlined_responses:
            resp = item.response
            resp = resp.to_json_dict() if hasattr(resp, "to_json_dict") else resp
            add(getattr(item, "key", None) or (item.metadata or {}).get("key"), resp)
    else:
        raw = c.files.download(file=dest.file_name)
        for line in raw.decode("utf-8").strip().split("\n"):
            if not line:
                continue
            obj = json.loads(line)
            add(obj.get("key") or (obj.get("metadata") or {}).get("key"),
                obj.get("response") or {})

    print(f"{len(items)} images to post-process (parallel x{WORKERS}) …")

    # 2. Post-process in parallel (the Gemini-flash facing-check is I/O-bound).
    written = failed = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(_process, sid, img, c): sid for sid, img in items}
        for i, fut in enumerate(futures, start=1):
            sid = futures[fut]
            try:
                ok = fut.result()
            except Exception as e:  # noqa: BLE001
                ok = False
                print(f"  ! fish_{sid}: {e}")
            written += ok
            failed += not ok
            if i % 200 == 0:
                print(f"  {i}/{len(items)} processed ({written} ok)")

    print(f"Collected: {written} written, {failed} missing/low.")
    remaining = sum(1 for s in json.loads(SEED_JSON.read_text()) if not has_png(int(s["id"])))
    print(f"{remaining} species still without art.")


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("submit")
    s.add_argument("--force", action="store_true", help="queue ALL species (uniform set)")
    s.add_argument("--ids", type=str, default="", help="comma-separated ids (test batch)")
    sub.add_parser("collect")
    args = ap.parse_args()

    if args.cmd == "submit":
        submit(args.force, args.ids)
    else:
        collect()


if __name__ == "__main__":
    main()
