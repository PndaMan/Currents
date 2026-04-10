"""
Fish species classifier training script.
Fine-tunes an iNat2021 pre-trained model on fish-only taxa.

Usage:
    python train.py --data ./data/fish --epochs 30 --batch-size 32

Requirements:
    pip install torch torchvision timm coremltools pillow
"""

import argparse
from pathlib import Path

import timm
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms


def get_transforms(train: bool = True, img_size: int = 300):
    if train:
        return transforms.Compose([
            transforms.RandomResizedCrop(img_size),
            transforms.RandomHorizontalFlip(),
            transforms.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.2, hue=0.1),
            transforms.RandomRotation(15),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
        ])
    return transforms.Compose([
        transforms.Resize(img_size + 32),
        transforms.CenterCrop(img_size),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])


def train(args):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    data_dir = Path(args.data)
    train_dir = data_dir / "train"
    val_dir = data_dir / "val"

    if not train_dir.exists():
        print(f"Error: {train_dir} not found.")
        print("Expected structure: data/fish/train/<species_name>/image.jpg")
        return

    # Datasets
    train_dataset = datasets.ImageFolder(str(train_dir), transform=get_transforms(train=True))
    val_dataset = datasets.ImageFolder(str(val_dir), transform=get_transforms(train=False))

    num_classes = len(train_dataset.classes)
    print(f"Found {num_classes} species, {len(train_dataset)} train / {len(val_dataset)} val images")

    # Save class mapping
    class_names = train_dataset.classes
    with open(data_dir / "classes.txt", "w") as f:
        for name in class_names:
            f.write(name + "\n")

    train_loader = DataLoader(
        train_dataset, batch_size=args.batch_size, shuffle=True,
        num_workers=4, pin_memory=True,
    )
    val_loader = DataLoader(
        val_dataset, batch_size=args.batch_size, shuffle=False,
        num_workers=4, pin_memory=True,
    )

    # Model — use timm with iNat2021 pretrained weights if available
    model = timm.create_model(
        args.model,
        pretrained=True,
        num_classes=num_classes,
    )
    model = model.to(device)

    # Freeze backbone for first few epochs, then unfreeze
    for param in model.parameters():
        param.requires_grad = False
    # Unfreeze classifier head
    if hasattr(model, "classifier"):
        for param in model.classifier.parameters():
            param.requires_grad = True
    elif hasattr(model, "fc"):
        for param in model.fc.parameters():
            param.requires_grad = True
    elif hasattr(model, "head"):
        for param in model.head.parameters():
            param.requires_grad = True

    optimizer = torch.optim.AdamW(filter(lambda p: p.requires_grad, model.parameters()), lr=args.lr)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    criterion = nn.CrossEntropyLoss(label_smoothing=0.1)

    best_acc = 0.0
    unfreeze_epoch = min(5, args.epochs // 3)

    for epoch in range(args.epochs):
        # Unfreeze all layers after warmup
        if epoch == unfreeze_epoch:
            print(f"Epoch {epoch}: unfreezing all layers")
            for param in model.parameters():
                param.requires_grad = True
            optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr * 0.1)
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
                optimizer, T_max=args.epochs - unfreeze_epoch
            )

        # Train
        model.train()
        running_loss = 0.0
        correct = 0
        total = 0
        for images, labels in train_loader:
            images, labels = images.to(device), labels.to(device)
            optimizer.zero_grad()
            outputs = model(images)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()

            running_loss += loss.item()
            _, predicted = outputs.max(1)
            total += labels.size(0)
            correct += predicted.eq(labels).sum().item()

        train_acc = 100.0 * correct / total

        # Validate
        model.eval()
        val_correct = 0
        val_total = 0
        with torch.no_grad():
            for images, labels in val_loader:
                images, labels = images.to(device), labels.to(device)
                outputs = model(images)
                _, predicted = outputs.max(1)
                val_total += labels.size(0)
                val_correct += predicted.eq(labels).sum().item()

        val_acc = 100.0 * val_correct / val_total
        scheduler.step()

        print(f"Epoch [{epoch+1}/{args.epochs}] "
              f"Train Loss: {running_loss/len(train_loader):.4f} "
              f"Train Acc: {train_acc:.1f}% "
              f"Val Acc: {val_acc:.1f}%")

        if val_acc > best_acc:
            best_acc = val_acc
            torch.save({
                "model_state_dict": model.state_dict(),
                "class_names": class_names,
                "num_classes": num_classes,
                "model_name": args.model,
                "val_acc": val_acc,
            }, data_dir / "best.pt")
            print(f"  Saved best model (val acc: {val_acc:.1f}%)")

    print(f"\nTraining complete. Best val accuracy: {best_acc:.1f}%")
    print(f"Model saved to {data_dir / 'best.pt'}")
    print(f"Run: python convert_coreml.py --model {data_dir / 'best.pt'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train fish species classifier")
    parser.add_argument("--data", type=str, default="./data/fish", help="Path to data directory")
    parser.add_argument("--model", type=str, default="efficientnet_b3", help="timm model name")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=1e-3)
    train(parser.parse_args())
