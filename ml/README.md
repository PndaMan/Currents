# Currents — Fish ID Model Training

## Strategy

Use an **iNat2021 pre-trained model** as the backbone, fine-tune on fish-only taxa, convert to CoreML.

## Setup

```bash
pip install ultralytics coremltools torch torchvision timm
```

## Training Steps

1. **Download iNaturalist fish images:**
   ```bash
   python download_fish_data.py --taxa Actinopterygii --min-images 50 --max-species 100
   ```

2. **Fine-tune:**
   ```bash
   python train.py --model efficientnet_b3 --pretrained inat2021 --epochs 30 --batch-size 32
   ```

3. **Convert to CoreML:**
   ```bash
   python convert_coreml.py --model best.pt --quantize int8
   ```

4. Copy output `FishID.mlpackage` to `ios/Currents/Resources/Models/`

## Hardware

Tested on RTX 3080 10GB. EfficientNet-B3 fine-tune fits comfortably in VRAM at batch=32.

## Datasets

| Dataset | Species | Images | Notes |
|---------|---------|--------|-------|
| iNaturalist (fish taxa) | 500+ | ~500K | Best coverage, filter by Actinopterygii/Chondrichthyes |
| Fish4Knowledge | 23 | 27K | Underwater footage |
| FishCLEF/LifeCLEF | 300+ | varies | Competition data |
| Roboflow fish datasets | varies | varies | Good for YOLO bounding box training |
