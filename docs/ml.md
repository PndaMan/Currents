# On-device fish identification

Currents ships a CoreML classifier that runs locally — no image ever leaves the phone. This document explains how the model gets into the app and how to swap in your own weights.

## Current state

`Core/ML/FishClassifier.swift` is wired to load `FishID.mlmodelc` from the main bundle at boot. Until a model is shipped it falls back to Vision's built-in `VNClassifyImageRequest`, which recognises a handful of common species but isn't species-accurate.

## Choosing a base model

We deliberately **don't train from scratch**. Fish species classification is a solved problem for the top few hundred common sport fish if you pick the right pre-trained backbone. The best public starting points:

| Model | Species | License | Notes |
|---|---|---|---|
| [FishNet (SLU-CVML)](https://github.com/faixan-khan/FishNet) | 17,357 | MIT (code), CC BY 4.0 (data) | Largest public fish dataset; ResNet-50 baseline weights convert to CoreML in ~20 lines |
| [Fishial.AI](https://github.com/fishial/Object-Detection-Model) | ~289 | CC BY-NC-SA 4.0 | Production-quality detector + classifier pipeline; **non-commercial only** |
| [iNaturalist 2021 vision](https://github.com/inaturalist/model-files) | ~2,500 fish taxa | code MIT, weights restricted | Best accuracy but redistribution is restricted to iNat / Seek |
| [FathomNet](https://github.com/fathomnet/models) | ~300 deep-sea | Apache 2.0 | Deep-sea only, not suited to recreational anglers |

**Recommended:** start with the **FishNet** ResNet-50 checkpoint (MIT-friendly) and either ship it directly or fine-tune the final layer on the ~300 species most anglers care about using `ml/train.py`.

## Training / fine-tuning

```bash
cd ml
pip install torch torchvision timm coremltools pillow
python train.py --data ./data/fish --model efficientnet_b3 --epochs 30
```

The training script expects a directory layout like:

```
data/fish/
  train/
    bass_largemouth/
    bass_smallmouth/
    ...
  val/
    bass_largemouth/
    ...
```

Any `ImageFolder`-compatible dataset works. Use the FishNet download scripts or scrape iNaturalist observations tagged `Actinopterygii`.

## Converting to CoreML

```bash
python convert_coreml.py --model ./data/fish/best.pt --quantize int8
```

This produces `FishID.mlpackage`. INT8 quantisation cuts size ~4× with a <1% accuracy loss on the validation set. Copy the output to `ios/Currents/Resources/Models/` and re-run `xcodegen generate`.

## Using the classifier at runtime

```swift
@Environment(AppState.self) var appState

let predictions = try await appState.fishClassifier.classify(image: uiImage, maxResults: 3)
// → [(species: "Largemouth Bass", confidence: 0.91), ...]
```

Inference runs on a background actor; call it from any async context. The returned species names map 1:1 to the `classes.txt` file saved during training, so you can join them back to the `species` table by `commonName`.

## Size budget

The app's size budget for the model is **under 30 MB**. That fits an INT8 ResNet-50 or an EfficientNet-B0 comfortably. Anything larger should be considered an optional download rather than a bundled asset.

## Known limitations

- Classification is centre-crop; if the fish is small in the frame, results degrade. A future iteration should detect + crop first (Fishial's pipeline) before classifying.
- The fallback Vision classifier only recognises broad animal categories. Don't rely on it for species-level data.
- Confidence scores are not calibrated — a 0.9 from one model is not comparable to a 0.9 from another. Compare within a single model only.
