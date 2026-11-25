"""Validate a banknote dataset manifest before training.

Checks: files exist and decode, labels are valid, class balance, minimum
images per class, duplicate images (exact hash), and — most importantly —
DATA LEAKAGE: the same physical note (note_id) must never appear in more than
one split.

Usage:
    python datasets/validate_dataset.py datasets/bdt/manifest.csv
Exit code 1 if any blocking problem is found.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import LABELS, read_manifest  # noqa: E402


def validate(manifest: Path, min_per_class: int = 30, check_decode: bool = True) -> list[str]:
    errors: list[str] = []
    warnings: list[str] = []
    samples = read_manifest(manifest)
    if not samples:
        return ["Manifest is empty."]

    hashes: dict[str, Path] = {}
    for s in samples:
        if s.label not in LABELS:
            errors.append(f"Invalid label {s.label!r} for {s.image_path}")
        if not s.note_id:
            errors.append(f"Missing note_id for {s.image_path}")
        if not s.image_path.is_file():
            errors.append(f"Missing file {s.image_path}")
            continue
        digest = hashlib.sha256(s.image_path.read_bytes()).hexdigest()
        if digest in hashes:
            warnings.append(f"Duplicate image: {s.image_path} == {hashes[digest]}")
        hashes[digest] = s.image_path
        if check_decode:
            import cv2

            if cv2.imread(str(s.image_path)) is None:
                errors.append(f"Cannot decode {s.image_path}")
        if s.torn_ratio is not None and not 0 <= s.torn_ratio <= 100:
            errors.append(f"torn_ratio out of range for {s.image_path}")

    # Leakage: one physical note → exactly one split.
    note_splits: dict[str, set[str]] = defaultdict(set)
    for s in samples:
        if s.split:
            note_splits[s.note_id].add(s.split)
    leaked = {n: sp for n, sp in note_splits.items() if len(sp) > 1}
    for n, sp in leaked.items():
        errors.append(f"DATA LEAKAGE: note_id {n} appears in splits {sorted(sp)}")

    # A note_id must not carry two different denominations.
    note_denoms: dict[str, set[str]] = defaultdict(set)
    for s in samples:
        note_denoms[s.note_id].add(s.label.split("_")[0])
    for n, d in note_denoms.items():
        if len(d) > 1:
            errors.append(f"note_id {n} labelled with multiple denominations {sorted(d)}")

    counts = Counter(s.label for s in samples)
    for label in LABELS:
        if counts[label] < min_per_class:
            warnings.append(f"Class {label}: only {counts[label]} images (< {min_per_class})")

    print(f"Images: {len(samples)}  physical notes: {len(note_denoms)}")
    for label in LABELS:
        print(f"  {label:14s} {counts[label]:6d}")
    for w in warnings:
        print("WARNING:", w)
    for e in errors:
        print("ERROR:", e)
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--min-per-class", type=int, default=30)
    ap.add_argument("--no-decode", action="store_true")
    a = ap.parse_args()
    errs = validate(a.manifest, a.min_per_class, not a.no_decode)
    print("OK" if not errs else f"{len(errs)} blocking error(s)")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
