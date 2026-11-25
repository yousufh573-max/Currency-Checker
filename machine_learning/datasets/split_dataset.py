"""Group-aware train/val/test split.

All photos of the same physical note (note_id) go to the SAME split, so the
model is evaluated on notes it has never seen (prevents data leakage).
Splits are stratified by denomination at the note level.

Usage:
    python datasets/split_dataset.py datasets/bdt/manifest.csv --val 0.15 --test 0.15 --seed 42
Writes the split column back into the manifest.
"""
from __future__ import annotations

import argparse
import random
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import read_manifest, write_manifest  # noqa: E402


def group_split(samples, val: float, test: float, seed: int):
    by_class: dict[str, list[str]] = defaultdict(list)
    note_class: dict[str, str] = {}
    for s in samples:
        note_class.setdefault(s.note_id, s.label.split("_")[0])
    for note, cls in note_class.items():
        by_class[cls].append(note)

    rng = random.Random(seed)
    assignment: dict[str, str] = {}
    for cls, notes in sorted(by_class.items()):
        notes = sorted(notes)
        rng.shuffle(notes)
        n = len(notes)
        n_test = max(1, round(n * test)) if n >= 3 else 0
        n_val = max(1, round(n * val)) if n - n_test >= 2 else 0
        for i, note in enumerate(notes):
            assignment[note] = "test" if i < n_test else "val" if i < n_test + n_val else "train"
    for s in samples:
        s.split = assignment[s.note_id]
    return samples


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--val", type=float, default=0.15)
    ap.add_argument("--test", type=float, default=0.15)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    samples = group_split(read_manifest(a.manifest), a.val, a.test, a.seed)
    write_manifest(a.manifest, samples)
    for sp in ("train", "val", "test"):
        print(sp, sum(1 for s in samples if s.split == sp), "images,", len({s.note_id for s in samples if s.split == sp}), "notes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
