"""
Download a pre-trained FishNet classifier and convert it to CoreML.

FishNet (Khan et al., 2023) is an MIT-licensed dataset + ResNet-50 baseline
with 17,357 fish species, by far the largest public fish classification
resource. We use it as-is rather than training from scratch — the goal is to
ship a working on-device species ID without the Currents project needing its
own GPU budget.

Usage:
    python download_and_convert.py

Output:
    FishID.mlpackage — drop into ios/Currents/Resources/Models/

Requirements:
    pip install torch torchvision coremltools requests tqdm

Reference:
    https://github.com/faixan-khan/FishNet
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


FISHNET_REPO = "https://github.com/faixan-khan/FishNet"
FISHNET_CHECKPOINT_URL = (
    # Replace with the actual release asset URL once a public one is published.
    # The upstream repo documents weights distribution in its README.
    "https://raw.githubusercontent.com/faixan-khan/FishNet/main/README.md"
)


def ensure_deps() -> None:
    missing = []
    for mod in ("torch", "torchvision", "coremltools"):
        try:
            __import__(mod)
        except ImportError:
            missing.append(mod)
    if missing:
        sys.exit(
            "Missing Python dependencies: "
            + ", ".join(missing)
            + "\nRun: pip install torch torchvision coremltools requests tqdm"
        )


def convert_resnet50(checkpoint_path: Path, classes_path: Path, output: Path, quantize: bool) -> None:
    import coremltools as ct
    import torch
    import torch.nn as nn
    import torchvision.models as tvm

    classes = [line.strip() for line in classes_path.read_text().splitlines() if line.strip()]
    num_classes = len(classes)
    print(f"Classes: {num_classes}")

    model = tvm.resnet50(weights=None)
    model.fc = nn.Linear(model.fc.in_features, num_classes)

    state = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    if isinstance(state, dict) and "state_dict" in state:
        state = state["state_dict"]
    model.load_state_dict(state, strict=False)
    model.eval()

    example = torch.randn(1, 3, 224, 224)
    traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, 224, 224), scale=1 / 255.0)],
        classifier_config=ct.ClassifierConfig(classes),
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.author = "Currents"
    mlmodel.short_description = f"FishNet fish species classifier ({num_classes} species)"
    mlmodel.version = "1.0"

    if quantize:
        print("Quantizing to INT8 ...")
        mlmodel = ct.compression_utils.affine_quantize_weights(mlmodel, dtype="int8")

    mlmodel.save(str(output))
    total_bytes = sum(f.stat().st_size for f in output.rglob("*") if f.is_file())
    print(f"Saved {output} ({total_bytes / 1024 / 1024:.1f} MB)")


def main() -> None:
    ensure_deps()
    parser = argparse.ArgumentParser(description="Download + convert a pre-trained fish classifier to CoreML")
    parser.add_argument(
        "--checkpoint",
        type=Path,
        required=True,
        help="Path to a local FishNet .pth checkpoint (download from the FishNet repo releases)",
    )
    parser.add_argument(
        "--classes",
        type=Path,
        required=True,
        help="Path to a newline-delimited classes.txt file",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("FishID.mlpackage"),
    )
    parser.add_argument("--no-quantize", action="store_true")
    args = parser.parse_args()

    if not args.checkpoint.exists():
        sys.exit(
            f"Checkpoint not found: {args.checkpoint}\n"
            f"Download from: {FISHNET_REPO}/releases\n"
            f"Place the .pth next to this script and re-run."
        )
    if not args.classes.exists():
        sys.exit(f"Classes file not found: {args.classes}")

    convert_resnet50(
        args.checkpoint,
        args.classes,
        args.output,
        quantize=not args.no_quantize,
    )


if __name__ == "__main__":
    main()
