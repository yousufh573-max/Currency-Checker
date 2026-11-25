"""Synthetic test images: textured 'notes' on a plain background.

These exercise the geometry/segmentation code paths deterministically. They
are NOT a substitute for evaluation on real banknote photographs.
"""
from __future__ import annotations

import cv2
import numpy as np

BG = (178, 190, 200)  # light beige/grey table (BGR)


def note_texture(w: int, h: int, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    b = 120 + 60 * np.sin(xx / 17.0) * np.cos(yy / 23.0)
    g = 150 + 50 * np.sin((xx + yy) / 31.0)
    r = 70 + 40 * np.cos(xx / 11.0)
    tex = np.dstack([b, g, r]) + rng.normal(0, 8, (h, w, 3))
    tex = np.clip(tex, 0, 255).astype(np.uint8)
    cv2.putText(tex, "20", (w - 140, 90), cv2.FONT_HERSHEY_SIMPLEX, 3, (30, 30, 120), 6)
    cv2.rectangle(tex, (20, 20), (w - 20, h - 20), (40, 60, 40), 3)
    return tex


def scene(note_w=600, note_h=280, img_w=1000, img_h=700, angle=0.0, offset=(0, 0), seed=0) -> tuple[np.ndarray, np.ndarray]:
    """Return (image, note_mask) with the note centred (plus offset) and rotated."""
    img = np.full((img_h, img_w, 3), BG, np.uint8)
    rng = np.random.default_rng(seed + 1)
    img = np.clip(img.astype(np.int16) + rng.normal(0, 3, img.shape).astype(np.int16), 0, 255).astype(np.uint8)
    tex = note_texture(note_w, note_h, seed)
    cx, cy = img_w / 2 + offset[0], img_h / 2 + offset[1]
    M = cv2.getRotationMatrix2D((note_w / 2, note_h / 2), angle, 1.0)
    M[0, 2] += cx - note_w / 2
    M[1, 2] += cy - note_h / 2
    warped = cv2.warpAffine(tex, M, (img_w, img_h))
    mask = cv2.warpAffine(np.full((note_h, note_w), 255, np.uint8), M, (img_w, img_h), flags=cv2.INTER_NEAREST)
    img[mask > 0] = warped[mask > 0]
    return img, mask


def tear(img: np.ndarray, mask: np.ndarray, fraction: float, seed: int = 0) -> tuple[np.ndarray, float]:
    """Remove a jagged chunk from the right end of the note; returns true torn %."""
    ys, xs = np.nonzero(mask)
    x0, x1 = xs.min(), xs.max()
    rng = np.random.default_rng(seed)
    out = img.copy()
    removed = mask.copy() * 0
    cut = x1 - fraction * (x1 - x0)
    h = img.shape[0]
    for y in range(h):
        jag = cut + rng.normal(0, 6) + 15 * np.sin(y / 9.0)
        removed[y, int(max(jag, x0)) :] = 255
    removed = cv2.bitwise_and(removed, mask)
    out[removed > 0] = img[0, 0]
    true_pct = 100.0 * np.count_nonzero(removed) / np.count_nonzero(mask)
    return out, true_pct


def encode(img: np.ndarray, ext: str = ".jpg") -> bytes:
    ok, buf = cv2.imencode(ext, img, [cv2.IMWRITE_JPEG_QUALITY, 92])
    assert ok
    return buf.tobytes()
