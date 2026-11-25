"""Banknote segmentation and torn-area estimation (classical computer vision).

Pipeline
--------
1. Background model: colour statistics of the image border (Lab space).
2. Foreground mask: pixels whose colour differs from the background.
   * Shadows (darker, but same chroma as background) are treated as background.
   * Skin-coloured pixels (fingers) are removed from the note mask and tracked
     separately so they are reported as *occlusion*, not as missing material.
3. Morphological clean-up, contour detection, multiple-note detection.
4. Expected geometry: minimum-area rectangle of the note's convex hull,
   corrected with the expected banknote aspect ratio when one end is missing.
5. Perspective correction: the note rectangle is warped to a canonical,
   axis-aligned crop (also used as classifier input).
6. Missing area = expected rectangle − remaining note material (incl. holes).
   Each missing region is inspected: straight-edged corner triangles are
   reported as possible folds; skin-dominated regions as occlusion.
7. Torn ratio (%) = (expected − remaining) / expected × 100.

When the expected area cannot be estimated reliably (note cut off by the
frame, low contrast with the background, fold or occlusion), the result is
marked unreliable so the note is never counted automatically.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

GENERIC_ASPECT = (1.75, 2.45)  # plausible long/short ratio range for BDT notes
CANONICAL_SHORT = 256


@dataclass
class TornAnalysis:
    found: bool
    reliable: bool = False
    torn_ratio: float | None = None
    bbox: tuple[int, int, int, int] | None = None
    flags: list[str] = field(default_factory=list)
    reason: str | None = None
    rectified: np.ndarray | None = None  # perspective-corrected BGR crop
    rect_mask: np.ndarray | None = None  # note mask in rectified space
    aspect: float | None = None
    debug: dict = field(default_factory=dict)


def _border_pixels(lab: np.ndarray, frac: float = 0.04) -> np.ndarray:
    h, w = lab.shape[:2]
    b = max(2, int(min(h, w) * frac))
    return np.concatenate(
        [lab[:b].reshape(-1, 3), lab[-b:].reshape(-1, 3), lab[:, :b].reshape(-1, 3), lab[:, -b:].reshape(-1, 3)]
    ).astype(np.float32)


def _skin_mask(img: np.ndarray) -> np.ndarray:
    ycrcb = cv2.cvtColor(img, cv2.COLOR_BGR2YCrCb)
    skin = cv2.inRange(ycrcb, (40, 138, 77), (240, 173, 127))
    return cv2.morphologyEx(skin, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))


def foreground_mask(img: np.ndarray) -> tuple[np.ndarray, np.ndarray, dict]:
    """Return (note_mask, skin_mask, stats). Masks are uint8 0/255."""
    blur = cv2.GaussianBlur(img, (5, 5), 0)
    lab = cv2.cvtColor(blur, cv2.COLOR_BGR2LAB).astype(np.float32)
    border = _border_pixels(lab)
    bg_med = np.median(border, axis=0)
    bg_mad = np.median(np.abs(border - bg_med), axis=0) * 1.4826 + 2.0  # robust std

    d = (lab - bg_med) / bg_mad
    d_l, d_ab = d[..., 0], np.sqrt(d[..., 1] ** 2 + d[..., 2] ** 2)
    # Shadow: darker than background but chroma unchanged -> background.
    shadow = (d_l < -1.0) & (d_ab < 2.5) & (lab[..., 0] > bg_med[0] * 0.25)
    # Larger chroma weight: notes are colourful; luminance is lighting-sensitive.
    dist = np.sqrt((0.5 * d_l) ** 2 + d_ab**2)
    fg = ((dist > 3.0) & ~shadow).astype(np.uint8) * 255

    k = max(3, (min(img.shape[:2]) // 150) | 1)
    fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, np.ones((k, k), np.uint8))
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((k * 2 + 1, k * 2 + 1), np.uint8))

    skin = _skin_mask(blur)
    # Only treat skin as occluder if the background itself is not skin-toned.
    border_skin_frac = float(_border_pixels(skin[..., None].repeat(3, 2)).mean() / 255)
    if border_skin_frac > 0.3:
        skin = np.zeros_like(skin)
    else:
        # Fingers/hands enter from outside the frame: keep only skin components
        # that reach the image border. Skin-toned *print* on a note (e.g. the
        # orange 50 Taka) stays part of the note.
        h, w = skin.shape
        n, labels, st, _ = cv2.connectedComponentsWithStats(skin)
        keep = np.zeros(n, bool)
        for i in range(1, n):
            x, y, bw, bh = st[i, 0], st[i, 1], st[i, 2], st[i, 3]
            keep[i] = x <= 2 or y <= 2 or x + bw >= w - 2 or y + bh >= h - 2
        skin = (keep[labels] * 255).astype(np.uint8)
    note = cv2.bitwise_and(fg, cv2.bitwise_not(skin))
    stats = {"bg_spread": float(bg_mad.mean()), "border_skin_frac": border_skin_frac}
    return note, skin, stats


def _order_box(pts: np.ndarray) -> np.ndarray:
    """Order 4 points TL, TR, BR, BL with the long side horizontal."""
    pts = pts.astype(np.float32)
    s, diff = pts.sum(1), np.diff(pts, axis=1).ravel()
    tl, br = pts[np.argmin(s)], pts[np.argmax(s)]
    tr, bl = pts[np.argmin(diff)], pts[np.argmax(diff)]
    box = np.array([tl, tr, br, bl], np.float32)
    if np.linalg.norm(box[0] - box[1]) < np.linalg.norm(box[1] - box[2]):
        box = np.roll(box, -1, axis=0)  # rotate so the long edge is on top
    return box


def _is_straight_corner_region(region: np.ndarray, w: int, h: int) -> bool:
    """A missing region bounded by straight edges at a corner looks like a fold."""
    cnts, _ = cv2.findContours(region, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cnts:
        return False
    c = max(cnts, key=cv2.contourArea)
    x, y, bw, bh = cv2.boundingRect(c)
    near_corner = (x <= 3 or x + bw >= w - 3) and (y <= 3 or y + bh >= h - 3)
    approx = cv2.approxPolyDP(c, 0.02 * cv2.arcLength(c, True), True)
    hull_perim = cv2.arcLength(cv2.convexHull(c), True)
    jaggedness = cv2.arcLength(c, True) / max(hull_perim, 1e-6)
    return near_corner and len(approx) <= 4 and jaggedness < 1.08


def analyze_torn(img: np.ndarray, expected_aspect: float | None = None) -> TornAnalysis:
    h, w = img.shape[:2]
    note, skin, stats = foreground_mask(img)
    img_area = h * w

    cnts, hierarchy = cv2.findContours(note, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return TornAnalysis(found=False, reason="no_note_found")
    outer = [i for i in range(len(cnts)) if hierarchy[0][i][3] == -1]
    outer.sort(key=lambda i: cv2.contourArea(cnts[i]), reverse=True)
    main = outer[0]
    main_area = cv2.contourArea(cnts[main])
    if main_area < 0.05 * img_area:
        return TornAnalysis(found=False, reason="note_too_small_or_absent", flags=["move_closer"])

    result = TornAnalysis(found=True, debug=stats)
    # Multiple notes: a second large, separate component.
    if len(outer) > 1 and cv2.contourArea(cnts[outer[1]]) > 0.25 * main_area:
        result.flags.append("multiple_notes")
        result.reason = "multiple_notes"

    x, y, bw, bh = cv2.boundingRect(cnts[main])
    result.bbox = (int(x), int(y), int(bw), int(bh))
    margin = 2
    if x <= margin or y <= margin or x + bw >= w - margin or y + bh >= h - margin:
        result.flags.append("touches_frame_edge")

    # Solid note mask: main contour filled, minus significant holes.
    solid = np.zeros_like(note)
    cv2.drawContours(solid, cnts, main, 255, cv2.FILLED)
    child = hierarchy[0][main][2]
    while child != -1:
        if cv2.contourArea(cnts[child]) > 0.002 * main_area:
            cv2.drawContours(solid, cnts, child, 0, cv2.FILLED)
        child = hierarchy[0][child][0]

    # Expected geometry from the convex hull, including skin occluders that
    # sit on the note (so fingers don't shrink the expected rectangle).
    hull_src = cnts[main]
    skin_on_note = cv2.bitwise_and(skin, cv2.dilate(solid, np.ones((15, 15), np.uint8)))
    if cv2.countNonZero(skin_on_note) > 0.01 * main_area:
        sk_pts = cv2.findNonZero(skin_on_note)
        hull_src = np.concatenate([hull_src, sk_pts])
    hull = cv2.convexHull(hull_src)
    (cx, cy), (rw, rh), angle = cv2.minAreaRect(hull)
    long_side, short_side = max(rw, rh), min(rw, rh)
    if short_side < 10:
        return TornAnalysis(found=False, reason="note_geometry_invalid")
    aspect = long_side / short_side
    result.aspect = round(aspect, 3)

    target_aspect = expected_aspect or sum(GENERIC_ASPECT) / 2
    lo, hi = GENERIC_ASPECT if expected_aspect is None else (expected_aspect * 0.93, expected_aspect * 1.07)
    expected_long = long_side
    if aspect < lo:
        # One end is missing: the long side is shorter than the note geometry implies.
        expected_long = short_side * target_aspect
        result.flags.append("geometry_extrapolated")
    elif aspect > hi * 1.12:
        result.reliable = False
        result.reason = result.reason or "unexpected_shape"
        result.flags.append("unexpected_shape")

    # Perspective correction to a canonical crop.
    box = _order_box(cv2.boxPoints(((cx, cy), (rw, rh), angle)))
    out_h = CANONICAL_SHORT
    out_w = int(round(CANONICAL_SHORT * long_side / short_side))
    dst = np.array([[0, 0], [out_w - 1, 0], [out_w - 1, out_h - 1], [0, out_h - 1]], np.float32)
    M = cv2.getPerspectiveTransform(box, dst)
    rectified = cv2.warpPerspective(img, M, (out_w, out_h), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0))
    rect_mask = cv2.warpPerspective(solid, M, (out_w, out_h), flags=cv2.INTER_NEAREST)
    rect_skin = cv2.warpPerspective(skin, M, (out_w, out_h), flags=cv2.INTER_NEAREST)
    result.rectified, result.rect_mask = rectified, rect_mask

    rect_area = float(out_w * out_h)
    expected_area = rect_area * (expected_long / long_side)
    remaining = float(cv2.countNonZero(rect_mask))

    # Inspect missing regions within the rectangle.
    missing = cv2.bitwise_not(rect_mask)
    n, labels, cc_stats, _ = cv2.connectedComponentsWithStats(missing)
    occluded_px = 0.0
    for i in range(1, n):
        area = cc_stats[i, cv2.CC_STAT_AREA]
        if area < 0.004 * rect_area:
            continue
        region = (labels == i).astype(np.uint8) * 255
        skin_frac = cv2.countNonZero(cv2.bitwise_and(region, rect_skin)) / area
        if skin_frac > 0.35:
            occluded_px += area
            if "occlusion" not in result.flags:
                result.flags.append("occlusion")
        elif _is_straight_corner_region(region, out_w, out_h) and "possible_fold" not in result.flags:
            result.flags.append("possible_fold")

    torn = (expected_area - remaining - occluded_px) / expected_area * 100.0
    torn = float(np.clip(torn, 0.0, 100.0))
    # Minor edge noise from segmentation is not damage.
    result.torn_ratio = round(torn if torn > 1.0 else 0.0, 1)

    unreliable = {"touches_frame_edge", "multiple_notes", "occlusion", "unexpected_shape"}
    if stats["bg_spread"] > 25:
        result.flags.append("busy_background")
        unreliable.add("busy_background")
    if "possible_fold" in result.flags and result.torn_ratio > 3:
        unreliable.add("possible_fold")
    blockers = [f for f in result.flags if f in unreliable]
    result.reliable = not blockers
    if blockers and not result.reason:
        result.reason = blockers[0]
    return result
