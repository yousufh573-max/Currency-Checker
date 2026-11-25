"""Train the BDT denomination classifier (MobileNetV3-Small, PyTorch).

Why a classifier and not a detector: the note is first localised and
perspective-corrected by the classical CV pipeline (backend/app/services/torn.py
and its Dart port), so the network only has to classify a rectified crop. A
compact classifier runs comfortably on phones via TFLite. (A YOLO segmentation
model can replace the CV localiser later — see README "Upgrading to YOLO".)

Usage:
    python training/train.py --manifest datasets/bdt/manifest.csv --epochs 40 --out weights/
"""
from __future__ import annotations

import argparse
import json
import random
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import INPUT_SIZE, LABELS, MEAN, STD, letterbox_rgb, read_manifest  # noqa: E402


class FoldOrTear:
    """Augmentation simulating damage/occlusion: erase a corner triangle or a
    jagged edge strip (fill with random background colour), or overlay a
    skin-toned 'finger'. Teaches the classifier to recognise partial notes."""

    def __init__(self, p: float = 0.35):
        self.p = p

    def __call__(self, img: np.ndarray) -> np.ndarray:
        if random.random() > self.p:
            return img
        h, w = img.shape[:2]
        out = img.copy()
        colour = tuple(int(c) for c in np.random.randint(0, 255, 3))
        kind = random.choice(["corner", "edge", "finger"])
        if kind == "corner":
            s = random.uniform(0.1, 0.35)
            cx, cy = random.choice([(0, 0), (w, 0), (0, h), (w, h)])
            pts = np.array([[cx, cy], [abs(cx - w * s), cy], [cx, abs(cy - h * s * 2)]], np.int32)
            cv2.fillPoly(out, [pts], colour)
        elif kind == "edge":
            frac = random.uniform(0.05, 0.3)
            x0 = int(w * (1 - frac))
            for y in range(h):
                jag = x0 + int(6 * np.sin(y / 5) + random.gauss(0, 3))
                out[y, max(0, jag):] = colour
        else:
            x = random.randint(0, w - 1)
            cv2.ellipse(out, (x, h), (int(w * 0.06), int(h * 0.35)), 0, 0, 360, (200, 150, 120), -1)
        return out


class BanknoteDataset(Dataset):
    def __init__(self, samples, train: bool):
        self.samples = samples
        self.train = train
        self.damage = FoldOrTear()
        aug = [
            transforms.RandomApply([transforms.RandomRotation(12)], p=0.5),
            transforms.RandomPerspective(0.25, p=0.4),
            transforms.ColorJitter(0.4, 0.4, 0.35, 0.04),
            transforms.RandomApply([transforms.GaussianBlur(5, (0.1, 2.0))], p=0.25),
            transforms.RandomHorizontalFlip(p=0.0),  # mirrored notes don't exist
        ] if train else []
        self.tf = transforms.Compose([transforms.ToPILImage(), *aug, transforms.ToTensor(), transforms.Normalize(MEAN, STD)])

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, i):
        s = self.samples[i]
        bgr = cv2.imread(str(s.image_path))
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        if self.train:
            rgb = self.damage(rgb)
            if random.random() < 0.5:  # notes can be upside down
                rgb = cv2.rotate(rgb, cv2.ROTATE_180)
        x = self.tf(letterbox_rgb(rgb, INPUT_SIZE))
        return x, LABELS.index(s.label)


def build_model(num_classes: int) -> nn.Module:
    m = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.IMAGENET1K_V1)
    m.classifier[3] = nn.Linear(m.classifier[3].in_features, num_classes)
    return m


def run_epoch(model, loader, device, opt=None):
    train = opt is not None
    model.train(train)
    total, correct, loss_sum = 0, 0, 0.0
    crit = nn.CrossEntropyLoss(label_smoothing=0.05)
    with torch.set_grad_enabled(train):
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            out = model(x)
            loss = crit(out, y)
            if train:
                opt.zero_grad()
                loss.backward()
                opt.step()
            loss_sum += loss.item() * len(y)
            correct += (out.argmax(1) == y).sum().item()
            total += len(y)
    return loss_sum / max(total, 1), correct / max(total, 1)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[1] / "weights")
    ap.add_argument("--version", default="1.0.0")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    random.seed(a.seed)
    np.random.seed(a.seed)
    torch.manual_seed(a.seed)
    samples = read_manifest(a.manifest)
    train = [s for s in samples if s.split == "train"]
    val = [s for s in samples if s.split == "val"]
    if not train or not val:
        print("Manifest has no train/val split. Run datasets/split_dataset.py first.")
        return 1
    leaked = {s.note_id for s in train} & {s.note_id for s in val}
    if leaked:
        print(f"Refusing to train: {len(leaked)} physical notes appear in both train and val.")
        return 1

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = build_model(len(LABELS)).to(device)
    tl = DataLoader(BanknoteDataset(train, True), batch_size=a.batch, shuffle=True, num_workers=2)
    vl = DataLoader(BanknoteDataset(val, False), batch_size=a.batch, num_workers=2)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, a.epochs)

    a.out.mkdir(parents=True, exist_ok=True)
    best = -1.0
    for ep in range(a.epochs):
        t0 = time.time()
        tr_loss, tr_acc = run_epoch(model, tl, device, opt)
        va_loss, va_acc = run_epoch(model, vl, device)
        sched.step()
        print(f"epoch {ep + 1:3d}  train {tr_loss:.3f}/{tr_acc:.3f}  val {va_loss:.3f}/{va_acc:.3f}  {time.time() - t0:.0f}s")
        if va_acc > best:
            best = va_acc
            torch.save(model.state_dict(), a.out / "banknote_classifier.pt")
    meta = {"model_version": a.version, "input_size": INPUT_SIZE, "mean": list(MEAN), "std": list(STD),
            "labels": LABELS, "architecture": "mobilenet_v3_small", "best_val_accuracy": best, "layout": "NCHW"}
    (a.out / "labels.json").write_text(json.dumps(meta, indent=2))
    print(f"Best val accuracy {best:.4f}. Saved to {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
