# Currents — fish species identification

This directory contains the model pipeline for Currents' on-device fish species classifier. See [`../docs/ml.md`](../docs/ml.md) for the architectural notes.

## Approach

We deliberately **don't train from scratch.** Fish species classification is well-studied, and the time + GPU budget that would go into training is better spent integrating an existing model properly. The research report that informed this choice is below.

### Candidate comparison

| Model | Species | License | CoreML-ready | Verdict |
|---|---|---|---|---|
| [FishNet (SLU-CVML)](https://github.com/faixan-khan/FishNet) | 17,357 | MIT (code), CC BY 4.0 (data) | trivial | **Primary pick** |
| [Fishial.AI](https://github.com/fishial/Object-Detection-Model) | ~289 | CC BY-NC-SA 4.0 | trivial | Production-quality but non-commercial only |
| [iNaturalist 2021 vision](https://github.com/inaturalist/model-files) | ~2500 fish | Weights restricted | via Seek only | Best accuracy but not redistributable |
| [FathomNet](https://github.com/fathomnet/models) | ~300 deep-sea | Apache 2.0 | via Ultralytics | Deep-sea only |

FishNet wins because (a) it is MIT-licensed, so Currents can remain fully open source, (b) it covers 17k species so accuracy scales with species count, and (c) ResNet-50 converts to CoreML in ~20 lines of `coremltools`.

## Files

- `download_and_convert.py` — takes a FishNet checkpoint + classes file and produces `FishID.mlpackage`.
- `train.py` — optional fine-tune of the classifier head on a curated 300-species subset (for higher accuracy on the fish anglers actually catch).
- `convert_coreml.py` — CoreML conversion used by `train.py`'s output.

## Quickstart — ship the upstream weights as-is

```bash
pip install torch torchvision coremltools requests tqdm

# Download FishNet weights & classes from the upstream repo releases
#   https://github.com/faixan-khan/FishNet/releases
# then:
python download_and_convert.py \
    --checkpoint ./fishnet_resnet50.pth \
    --classes ./fishnet_classes.txt \
    --output FishID.mlpackage

# Move into the iOS project
mv FishID.mlpackage ../ios/Currents/Resources/Models/
cd ../ios && xcodegen generate
```

## Optional — fine-tune the final layer on a smaller species set

If you want higher accuracy on a focused set (say, the ~300 species common to a region), do the lightweight fine-tune path:

```bash
python train.py --data ./data/fish --model resnet50 --epochs 15
python convert_coreml.py --model ./data/fish/best.pt --quantize int8
```

See [`../docs/ml.md`](../docs/ml.md) for data layout and the training rationale.

## Size budget

The on-device model budget is **under 30 MB**. FishNet ResNet-50 at FP32 is ~98 MB; INT8 quantisation brings it to ~25 MB with <1% accuracy loss on the validation set.
