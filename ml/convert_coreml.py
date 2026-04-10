"""
Convert a trained PyTorch fish classifier to CoreML format.

Usage:
    python convert_coreml.py --model ./data/fish/best.pt --quantize int8

Output:
    FishID.mlpackage in the current directory
"""

import argparse
from pathlib import Path

import coremltools as ct
import timm
import torch


def convert(args):
    checkpoint = torch.load(args.model, map_location="cpu", weights_only=False)

    model_name = checkpoint["model_name"]
    num_classes = checkpoint["num_classes"]
    class_names = checkpoint["class_names"]

    print(f"Model: {model_name}, Classes: {num_classes}")
    print(f"Original val accuracy: {checkpoint['val_acc']:.1f}%")

    # Recreate model and load weights
    model = timm.create_model(model_name, pretrained=False, num_classes=num_classes)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    # Trace with example input
    example = torch.randn(1, 3, 300, 300)
    traced = torch.jit.trace(model, example)

    # Convert to CoreML
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, 300, 300), scale=1/255.0)],
        classifier_config=ct.ClassifierConfig(class_names),
        minimum_deployment_target=ct.target.iOS17,
    )

    # Add metadata
    mlmodel.author = "Currents"
    mlmodel.short_description = f"Fish species classifier ({num_classes} species)"
    mlmodel.version = "1.0"

    output_path = "FishID.mlpackage"

    if args.quantize == "int8":
        print("Quantizing to INT8...")
        mlmodel = ct.compression_utils.affine_quantize_weights(mlmodel, dtype="int8")
        print("Quantized.")

    mlmodel.save(output_path)
    print(f"Saved to {output_path}")

    # Report size
    import os
    size_mb = sum(
        f.stat().st_size for f in Path(output_path).rglob("*") if f.is_file()
    ) / (1024 * 1024)
    print(f"Model size: {size_mb:.1f} MB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert fish classifier to CoreML")
    parser.add_argument("--model", type=str, required=True, help="Path to best.pt checkpoint")
    parser.add_argument("--quantize", type=str, choices=["none", "int8"], default="int8")
    convert(parser.parse_args())
