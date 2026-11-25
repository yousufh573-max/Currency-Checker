"""Tests for dataset validation and leakage-safe splitting (no PyTorch needed)."""
import sys
from pathlib import Path

import cv2
import numpy as np

ML = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ML))
sys.path.insert(0, str(ML / "datasets"))
from common import read_manifest, write_manifest  # noqa: E402
from split_dataset import group_split  # noqa: E402
from validate_dataset import validate  # noqa: E402


def make_dataset(tmp: Path, notes_per_class=6, photos_per_note=3):
    rows = ["image_path,note_id,denomination,side,series,torn_ratio,split"]
    rng = np.random.default_rng(0)
    for d in (20, 100):
        for n in range(notes_per_class):
            for k in range(photos_per_note):
                p = tmp / f"img/{d}_{n}_{k}.jpg"
                p.parent.mkdir(parents=True, exist_ok=True)
                cv2.imwrite(str(p), rng.integers(0, 255, (40, 80, 3), dtype=np.uint8))
                rows.append(f"img/{p.name},note-{d}-{n},{d},front,2020,,")
    m = tmp / "manifest.csv"
    m.write_text("\n".join(rows))
    return m


def test_group_split_keeps_each_physical_note_in_one_split(tmp_path):
    m = make_dataset(tmp_path)
    samples = group_split(read_manifest(m), 0.2, 0.2, seed=1)
    splits = {}
    for s in samples:
        splits.setdefault(s.note_id, set()).add(s.split)
    assert all(len(v) == 1 for v in splits.values())
    assert {s.split for s in samples} == {"train", "val", "test"}
    write_manifest(m, samples)
    assert validate(m, min_per_class=0) == []


def test_validator_detects_leakage_and_bad_labels(tmp_path):
    m = make_dataset(tmp_path)
    samples = group_split(read_manifest(m), 0.2, 0.2, seed=1)
    samples[0].split = "test" if samples[0].split != "test" else "train"  # leak one photo
    samples[1].label = "30_front"  # invalid denomination
    write_manifest(m, samples)
    errors = validate(m, min_per_class=0)
    assert any("DATA LEAKAGE" in e for e in errors)
    assert any("Invalid label" in e for e in errors)
