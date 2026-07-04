#!/usr/bin/env python3
"""
Convert BioCLIP into an on-device fish identifier for Currents.

BioCLIP (imageomics/bioclip) is a CLIP model trained on the Tree of Life
(iNaturalist + GBIF + EOL) — a genuine species-classification model that
knows gamefish (largemouth bass, brook trout, carp species, …). We use it in
a zero-shot setup targeting *exactly* the app's species list:

  1. Convert BioCLIP's **image encoder** (ViT-B/16, 224px) to a single-file
     CoreML model. CLIP normalisation (mean/std) is baked into the image
     input so the app can feed a raw pixel buffer.
  2. Precompute a **text embedding per species** using BioCLIP's text encoder
     and its taxonomic prompt, from the app's species_seed.json. These are
     written to a compact resource bundled in the app.

On device the app runs the CoreML image encoder on the (cropped) catch photo
to get a 512-d embedding, then cosine-matches it against the bundled species
text embeddings — offline, over the exact app label space.

Usage
-----
    pip install open_clip_torch torch coremltools numpy
    python ml/bioclip_to_coreml.py --out FishID.mlmodel

Outputs
-------
    FishID.mlmodel                                  (image encoder, ~90MB fp16)
    ios/Currents/Resources/Data/species_embeddings.json
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SEED_JSON = REPO / "ios/Currents/Resources/Data/species_seed.json"
EMB_OUT = REPO / "ios/Currents/Resources/Data/species_embeddings.bin"

MODEL = "hf-hub:imageomics/bioclip"
IMG_SIZE = 224
# OpenCLIP normalisation constants.
CLIP_MEAN = (0.48145466, 0.4578275, 0.40821073)
CLIP_STD = (0.26862954, 0.26130258, 0.27577711)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("FishID.mlmodel"))
    args = ap.parse_args()

    import numpy as np
    import open_clip
    import torch
    import coremltools as ct

    print(f"Loading {MODEL} …")
    model, _, _ = open_clip.create_model_and_transforms(MODEL)
    tokenizer = open_clip.get_tokenizer(MODEL)
    model.eval()

    # ---- 1. Species text embeddings ---------------------------------------
    species = json.loads(SEED_JSON.read_text())
    print(f"Embedding {len(species)} species names …")
    # BioCLIP's recommended prompt uses the scientific name.
    prompts, ids = [], []
    for sp in species:
        sci = sp["scientificName"]
        common = sp.get("commonName", "")
        prompts.append(f"a photo of {sci} ({common})")
        ids.append(int(sp["id"]))

    with torch.no_grad():
        text_features = []
        for i in range(0, len(prompts), 256):
            toks = tokenizer(prompts[i:i + 256])
            feats = model.encode_text(toks)
            feats = feats / feats.norm(dim=-1, keepdim=True)
            text_features.append(feats)
        text_features = torch.cat(text_features).float().numpy()

    dim = text_features.shape[1]
    # Compact binary: [uint32 count][uint32 dim] then per species: int32 id + dim float32
    with EMB_OUT.open("wb") as f:
        f.write(struct.pack("<II", len(ids), dim))
        for sid, vec in zip(ids, text_features):
            f.write(struct.pack("<i", sid))
            f.write(vec.astype("<f4").tobytes())
    print(f"Wrote {EMB_OUT.relative_to(REPO)} ({EMB_OUT.stat().st_size/1024:.0f} KB, dim {dim})")

    # ---- 2. Image encoder → CoreML ----------------------------------------
    print("Tracing image encoder …")

    class Visual(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            f = self.m.encode_image(x)
            return f / f.norm(dim=-1, keepdim=True)

    visual = Visual(model).eval()
    example = torch.rand(1, 3, IMG_SIZE, IMG_SIZE)
    traced = torch.jit.trace(visual, example)

    # Bake CLIP normalisation into the image input: (pixel/255 - mean)/std
    # => scale = 1/(255*std), bias = -mean/std
    scale = [1.0 / (255.0 * s) for s in CLIP_STD]
    bias = [-m / s for m, s in zip(CLIP_MEAN, CLIP_STD)]
    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, IMG_SIZE, IMG_SIZE),
        scale=scale[0],  # per-channel handled via bias below when needed
        bias=bias,
        color_layout=ct.colorlayout.RGB,
    )

    single_file = args.out.suffix == ".mlmodel"
    kwargs = dict(inputs=[image_input])
    if single_file:
        kwargs["convert_to"] = "neuralnetwork"
    else:
        kwargs["minimum_deployment_target"] = ct.target.iOS16

    mlmodel = ct.convert(traced, **kwargs)
    mlmodel.author = "Currents / BioCLIP"
    mlmodel.short_description = "BioCLIP image encoder (512-d embedding) for fish ID"
    mlmodel.save(str(args.out))
    size = args.out.stat().st_size if args.out.is_file() else sum(
        f.stat().st_size for f in args.out.rglob("*") if f.is_file())
    print(f"Saved {args.out} ({size/1024/1024:.0f} MB)")


if __name__ == "__main__":
    main()
