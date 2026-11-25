"""Evaluate a trained classifier on the held-out TEST split.

Reports:
  * overall and per-denomination recognition accuracy
  * confusion matrix (CSV, and PNG if matplotlib is installed)
  * confidence-threshold sweep: coverage vs. accuracy of accepted notes,
    to choose MIN_CONFIDENCE (the app only counts notes above it)
  * torn-ratio estimation error (MAE / max error) using the production CV
    pipeline, for images that have a ground-truth `torn_ratio`

Runs the exported ONNX model through the same code path as the backend.

Usage:
    python evaluation/evaluate.py --manifest datasets/bdt/manifest.csv \
        --model weights/banknote_classifier.onnx --labels weights/labels.json --out evaluation/report
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "machine_learning"))
sys.path.insert(0, str(ROOT / "backend"))
from common import LABELS, read_manifest  # noqa: E402
from app.core.config import NOTE_DIMENSIONS_MM, Settings  # noqa: E402
from app.services.classifier import BanknoteClassifier, parse_label  # noqa: E402
from app.services.torn import analyze_torn  # noqa: E402


def denom_of(label: str) -> str:
    return label.split("_")[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--model", type=Path, required=True)
    ap.add_argument("--labels", type=Path, required=True)
    ap.add_argument("--split", default="test")
    ap.add_argument("--out", type=Path, default=Path("evaluation/report"))
    a = ap.parse_args()

    clf = BanknoteClassifier(Settings(_env_file=None, model_path=a.model, model_labels_path=a.labels))
    if not clf.loaded:
        print(clf.error)
        return 1
    samples = [s for s in read_manifest(a.manifest) if s.split == a.split]
    if not samples:
        print(f"No samples in split {a.split!r}")
        return 1

    classes = sorted({denom_of(l) for l in LABELS}, key=lambda c: (not c.isdigit(), int(c) if c.isdigit() else 0))
    idx = {c: i for i, c in enumerate(classes)}
    cm = np.zeros((len(classes), len(classes)), int)
    records = []
    torn_err = []
    for s in samples:
        img = cv2.imread(str(s.image_path))
        torn = analyze_torn(img)
        crop = torn.rectified if torn.found and torn.rectified is not None else img
        p = clf.predict(crop)
        truth, pred = denom_of(s.label), denom_of(p.label)
        cm[idx[truth], idx[pred]] += 1
        records.append((truth, pred, p.confidence))
        if s.torn_ratio is not None and torn.found:
            d, _ = parse_label(s.label)
            est = analyze_torn(img, expected_aspect=(NOTE_DIMENSIONS_MM[d][0] / NOTE_DIMENSIONS_MM[d][1]) if d else None)
            if est.torn_ratio is not None:
                torn_err.append(abs(est.torn_ratio - s.torn_ratio))

    a.out.mkdir(parents=True, exist_ok=True)
    acc = float(np.trace(cm) / cm.sum())
    per_class = {c: float(cm[i, i] / cm[i].sum()) if cm[i].sum() else None for c, i in idx.items()}
    with (a.out / "confusion_matrix.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["truth\\pred", *classes])
        for c, i in idx.items():
            w.writerow([c, *cm[i].tolist()])

    sweep = []
    for th in np.arange(0.5, 1.0, 0.025):
        acc_set = [(t, p) for t, p, c in records if c >= th]
        cov = len(acc_set) / len(records)
        correct = sum(t == p for t, p in acc_set) / len(acc_set) if acc_set else None
        sweep.append({"threshold": round(float(th), 3), "coverage": round(cov, 4), "accuracy_of_accepted": correct})

    report = {
        "split": a.split,
        "images": len(samples),
        "accuracy": acc,
        "per_class_accuracy": per_class,
        "threshold_sweep": sweep,
        "torn_ratio_mae": float(np.mean(torn_err)) if torn_err else None,
        "torn_ratio_max_error": float(np.max(torn_err)) if torn_err else None,
        "torn_ratio_samples": len(torn_err),
        "model_version": clf.model_version,
    }
    (a.out / "report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps({k: report[k] for k in ("images", "accuracy", "torn_ratio_mae")}, indent=2))
    print("Per class:", per_class)
    print("Choose MIN_CONFIDENCE where accuracy_of_accepted meets your target (see report.json).")

    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, ax = plt.subplots(figsize=(8, 7))
        ax.imshow(cm, cmap="Blues")
        ax.set_xticks(range(len(classes)), classes, rotation=45)
        ax.set_yticks(range(len(classes)), classes)
        for i in range(len(classes)):
            for j in range(len(classes)):
                ax.text(j, i, cm[i, j], ha="center", va="center", fontsize=8)
        ax.set_xlabel("Predicted")
        ax.set_ylabel("True")
        fig.tight_layout()
        fig.savefig(a.out / "confusion_matrix.png", dpi=150)
    except ImportError:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
