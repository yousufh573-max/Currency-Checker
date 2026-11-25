"""Shared constants and preprocessing for training, evaluation and export.

The preprocessing here MUST match backend/app/services/classifier.py and
mobile/lib/services/recognition/on_device_engine.dart: RGB, letterbox to a
square with grey (114) padding, scale to [0,1], then (x - mean) / std.
"""
from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

import numpy as np

DENOMINATIONS = (2, 5, 10, 20, 50, 100, 200, 500, 1000)
SIDES = ("front", "back")
NEGATIVE_LABEL = "not_banknote"
INPUT_SIZE = 224
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)

# Class list: one class per denomination+side, plus a negative class.
LABELS = [f"{d}_{s}" for d in DENOMINATIONS for s in SIDES] + [NEGATIVE_LABEL]


@dataclass
class Sample:
    image_path: Path
    note_id: str          # identifies the PHYSICAL note (all photos of one note share it)
    label: str            # e.g. "20_front" or "not_banknote"
    series: str = ""
    torn_ratio: float | None = None  # ground-truth missing area %, if annotated
    split: str = ""


def read_manifest(path: Path) -> list[Sample]:
    root = path.parent
    out: list[Sample] = []
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            denom, side = row.get("denomination", "").strip(), row.get("side", "").strip()
            label = NEGATIVE_LABEL if denom in ("", "none", NEGATIVE_LABEL) else f"{denom}_{side}"
            tr = row.get("torn_ratio", "").strip()
            out.append(Sample(
                image_path=(root / row["image_path"]).resolve(),
                note_id=row["note_id"].strip(),
                label=label,
                series=row.get("series", "").strip(),
                torn_ratio=float(tr) if tr else None,
                split=row.get("split", "").strip(),
            ))
    return out


def write_manifest(path: Path, samples: list[Sample]) -> None:
    root = path.parent
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["image_path", "note_id", "denomination", "side", "series", "torn_ratio", "split"])
        for s in samples:
            denom, _, side = s.label.partition("_") if s.label != NEGATIVE_LABEL else (NEGATIVE_LABEL, "", "")
            w.writerow([Path(s.image_path).resolve().relative_to(root.resolve()).as_posix(), s.note_id, denom, side, s.series,
                        "" if s.torn_ratio is None else s.torn_ratio, s.split])


def letterbox_rgb(rgb: np.ndarray, size: int = INPUT_SIZE) -> np.ndarray:
    import cv2

    h, w = rgb.shape[:2]
    s = size / max(h, w)
    r = cv2.resize(rgb, (max(1, round(w * s)), max(1, round(h * s))), interpolation=cv2.INTER_AREA)
    canvas = np.full((size, size, 3), 114, np.uint8)
    y0, x0 = (size - r.shape[0]) // 2, (size - r.shape[1]) // 2
    canvas[y0:y0 + r.shape[0], x0:x0 + r.shape[1]] = r
    return canvas
