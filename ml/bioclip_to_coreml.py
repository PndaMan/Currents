#!/usr/bin/env python3
"""
Convert BioCLIP into an on-device fish identifier for Currents.

BioCLIP (imageomics/bioclip) is a CLIP model trained on the Tree of Life
(iNaturalist + GBIF + EOL) — a genuine species-classification model that
knows gamefish (largemouth bass, brook trout, carp species, …). We use it in
a zero-shot / few-shot setup targeting *exactly* the app's species list:

  1. Convert BioCLIP's **image encoder** to a single-file CoreML model. CLIP
     normalisation (mean/std) is baked into the model so the app can feed a
     raw pixel buffer. Optionally 8-bit weight-quantised to shrink the file.
  2. Precompute a **species embedding** per app species. Two ingredients,
     blended and L2-normalised:
        • a *text* embedding — an **ensemble** of several prompt templates
          (name, common name, family) averaged, which is far more robust than
          a single prompt and cuts confident mis-IDs.
        • an optional *visual prototype* — the mean image embedding of a few
          real reference photos pulled from iNaturalist for that species
          ("more photos"). Few-shot prototypes beat text-only zero-shot by a
          wide margin, especially for look-alike species.
     Per-species the photo fetch is best-effort: any failure falls back to the
     text ensemble, so the run never aborts on a flaky download.

On device the app runs the CoreML image encoder on the (cropped) catch photo
to get an embedding, then cosine-matches it against the bundled species
embeddings — offline, over the exact app label space. The embedding dimension
is written in the .bin header and read dynamically, so switching backbone
(e.g. ViT-B/16 512-d → BioCLIP-2 ViT-L/14 768-d) needs no app change.

Usage
-----
    pip install open_clip_torch torch coremltools numpy pillow requests
    python ml/bioclip_to_coreml.py --out FishID.mlpackage

Key flags
---------
    --model          open_clip model spec (default hf-hub:imageomics/bioclip)
    --photos N       reference photos per species for the visual prototype
                     (0 = text-only). Cached under ml/.photo_cache.
    --text-weight W  blend weight for text vs image prototype (0..1, default .5)
    --quantize-bits  8 to int8-quantise the image encoder weights (0 = off)

Outputs
-------
    FishID.mlpackage                                (image encoder)
    ios/Currents/Resources/Data/species_embeddings.bin
"""

from __future__ import annotations

import argparse
import json
import struct
import time
import hashlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SEED_JSON = REPO / "ios/Currents/Resources/Data/species_seed.json"
EMB_OUT = REPO / "ios/Currents/Resources/Data/species_embeddings.bin"
PHOTO_CACHE = REPO / "ml/.photo_cache"

# Keep the image input fixed at 224px — the app feeds a 224px buffer regardless
# of backbone, so all supported CLIP variants must use this native size.
IMG_SIZE = 224
# OpenCLIP normalisation constants.
CLIP_MEAN = (0.48145466, 0.4578275, 0.40821073)
CLIP_STD = (0.26862954, 0.26130258, 0.27577711)

# Named backbones the `variant` workflow input can select.
MODEL_ALIASES = {
    "bioclip": "hf-hub:imageomics/bioclip",
    "bioclip-2": "hf-hub:imageomics/bioclip-2",
    "bioclip2": "hf-hub:imageomics/bioclip-2",
}


def prompt_ensemble(sci: str, common: str, family: str) -> list[str]:
    """Several complementary prompts per species, averaged downstream.

    BioCLIP responds best to the scientific name; adding the common name and
    family disambiguates look-alikes and stabilises the embedding."""
    sci = (sci or "").strip()
    common = (common or "").strip()
    family = (family or "").strip()
    prompts = [f"a photo of {sci}."]
    if common:
        prompts.append(f"a photo of {common}.")
        prompts.append(f"a photo of {sci}, commonly known as {common}.")
        prompts.append(f"a photo of a {common}, a species of fish.")
    if family:
        prompts.append(f"a photo of {sci}, a fish in the family {family}.")
    return prompts


def fetch_reference_photos(sci: str, want: int, session) -> list:
    """Best-effort: return up to `want` PIL images for a species from
    iNaturalist. Cached on disk so reruns are cheap. Never raises."""
    from PIL import Image
    import io

    if want <= 0:
        return []
    key = hashlib.sha1(sci.encode()).hexdigest()[:16]
    sp_dir = PHOTO_CACHE / key
    sp_dir.mkdir(parents=True, exist_ok=True)

    cached = sorted(sp_dir.glob("*.jpg"))
    images = []
    for p in cached[:want]:
        try:
            images.append(Image.open(p).convert("RGB"))
        except Exception:
            pass
    if len(images) >= want:
        return images

    # Look up the taxon, then pull its curated taxon_photos.
    try:
        r = session.get(
            "https://api.inaturalist.org/v1/taxa",
            params={"q": sci, "rank": "species", "per_page": 1, "is_active": "true"},
            headers={"User-Agent": "Currents Fishing App (model builder)"},
            timeout=15,
        )
        if r.status_code != 200:
            return images
        results = r.json().get("results", [])
        if not results:
            return images
        taxon = results[0]
        urls = []
        if taxon.get("default_photo", {}).get("medium_url"):
            urls.append(taxon["default_photo"]["medium_url"])
        for tp in taxon.get("taxon_photos", []):
            photo = tp.get("photo", {})
            u = photo.get("medium_url") or photo.get("url")
            if u:
                urls.append(u)
        seen = set()
        for i, u in enumerate(urls):
            if len(images) >= want:
                break
            if u in seen:
                continue
            seen.add(u)
            try:
                pr = session.get(u, timeout=15)
                if pr.status_code != 200:
                    continue
                img = Image.open(io.BytesIO(pr.content)).convert("RGB")
                img.save(sp_dir / f"{i}.jpg", "JPEG", quality=85)
                images.append(img)
            except Exception:
                continue
        # Be polite to the public API.
        time.sleep(0.7)
    except Exception:
        pass
    return images


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("FishID.mlpackage"))
    ap.add_argument("--model", default="hf-hub:imageomics/bioclip",
                    help="open_clip spec or alias: bioclip, bioclip-2")
    ap.add_argument("--photos", type=int, default=0,
                    help="reference photos per species for the visual prototype")
    ap.add_argument("--text-weight", type=float, default=0.5,
                    help="blend weight for text vs image prototype (0..1)")
    ap.add_argument("--quantize-bits", type=int, default=0,
                    help="8 to int8-quantise the image encoder weights")
    args = ap.parse_args()

    model_spec = MODEL_ALIASES.get(args.model, args.model)

    import numpy as np
    import open_clip
    import torch
    import coremltools as ct

    print(f"Loading {model_spec} …")
    model, _, preprocess = open_clip.create_model_and_transforms(model_spec)
    tokenizer = open_clip.get_tokenizer(model_spec)
    model.eval()

    species = json.loads(SEED_JSON.read_text())
    print(f"{len(species)} app species")

    # ---- 1. Text-ensemble embeddings --------------------------------------
    print("Embedding species prompts (ensemble) …")
    ids: list[int] = []
    text_vecs: list = []
    with torch.no_grad():
        for sp in species:
            prompts = prompt_ensemble(sp["scientificName"], sp.get("commonName", ""),
                                      sp.get("family", ""))
            toks = tokenizer(prompts)
            feats = model.encode_text(toks)
            feats = feats / feats.norm(dim=-1, keepdim=True)
            mean = feats.mean(dim=0)
            mean = mean / mean.norm()
            ids.append(int(sp["id"]))
            text_vecs.append(mean.float().numpy())
    text_features = np.stack(text_vecs)
    dim = text_features.shape[1]
    print(f"  text embeddings: {text_features.shape}")

    # ---- 2. Optional visual prototypes from reference photos --------------
    final_features = text_features.copy()
    if args.photos > 0:
        import requests
        session = requests.Session()
        tw = float(min(1.0, max(0.0, args.text_weight)))
        got = 0
        with torch.no_grad():
            for idx, sp in enumerate(species):
                imgs = fetch_reference_photos(sp["scientificName"], args.photos, session)
                if not imgs:
                    continue
                batch = torch.stack([preprocess(im) for im in imgs])
                emb = model.encode_image(batch)
                emb = emb / emb.norm(dim=-1, keepdim=True)
                proto = emb.mean(dim=0)
                proto = (proto / proto.norm()).float().numpy()
                blended = tw * text_features[idx] + (1.0 - tw) * proto
                n = np.linalg.norm(blended)
                if n > 0:
                    final_features[idx] = blended / n
                got += 1
                if idx % 100 == 0:
                    print(f"  photos {idx}/{len(species)} (prototypes so far: {got})")
        print(f"  built visual prototypes for {got}/{len(species)} species")

    # ---- 3. Write compact binary ------------------------------------------
    # [uint32 count][uint32 dim] then per species: int32 id + dim float32
    with EMB_OUT.open("wb") as f:
        f.write(struct.pack("<II", len(ids), dim))
        for sid, vec in zip(ids, final_features):
            f.write(struct.pack("<i", sid))
            f.write(vec.astype("<f4").tobytes())
    print(f"Wrote {EMB_OUT.relative_to(REPO)} ({EMB_OUT.stat().st_size/1024:.0f} KB, dim {dim})")

    # ---- 4. Image encoder → CoreML ----------------------------------------
    print("Tracing image encoder …")

    class Visual(torch.nn.Module):
        def __init__(self, m, mean, std):
            super().__init__()
            self.m = m
            self.register_buffer("mean", torch.tensor(mean).view(1, 3, 1, 1))
            self.register_buffer("std", torch.tensor(std).view(1, 3, 1, 1))

        def forward(self, x):  # x in [0,1], RGB
            x = (x - self.mean) / self.std
            f = self.m.encode_image(x)
            return f / f.norm(dim=-1, keepdim=True)

    visual = Visual(model, CLIP_MEAN, CLIP_STD).eval()
    example = torch.rand(1, 3, IMG_SIZE, IMG_SIZE)  # [0,1]
    traced = torch.jit.trace(visual, example, check_trace=False)

    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, IMG_SIZE, IMG_SIZE),
        scale=1.0 / 255.0,
        bias=[0.0, 0.0, 0.0],
        color_layout=ct.colorlayout.RGB,
    )

    mlmodel = ct.convert(
        traced,
        inputs=[image_input],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
    )

    # ---- 5. Optional 8-bit weight quantisation ----------------------------
    if args.quantize_bits and args.quantize_bits > 0:
        print(f"Quantising weights to {args.quantize_bits}-bit …")
        try:
            from coremltools.optimize.coreml import (
                OpLinearQuantizerConfig, OptimizationConfig, linear_quantize_weights,
            )
            op_cfg = OpLinearQuantizerConfig(mode="linear_symmetric",
                                             dtype=f"int{args.quantize_bits}")
            cfg = OptimizationConfig(global_config=op_cfg)
            mlmodel = linear_quantize_weights(mlmodel, config=cfg)
            print("  quantised.")
        except Exception as e:
            print(f"  quantisation skipped ({e}); shipping fp16.")

    mlmodel.author = "Currents / BioCLIP"
    mlmodel.short_description = f"BioCLIP image encoder ({dim}-d embedding) for fish ID"
    mlmodel.save(str(args.out))
    size = args.out.stat().st_size if args.out.is_file() else sum(
        f.stat().st_size for f in args.out.rglob("*") if f.is_file())
    print(f"Saved {args.out} ({size/1024/1024:.0f} MB)")


if __name__ == "__main__":
    main()
