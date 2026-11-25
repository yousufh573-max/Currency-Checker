"""Image quality assessment: blur, brightness, contrast, resolution."""
from __future__ import annotations

import cv2
import numpy as np

from app.core.config import Settings
from app.schemas.analysis import QualityResult


def assess_quality(img: np.ndarray, settings: Settings) -> QualityResult:
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    # Normalise resolution so the blur metric is comparable across inputs.
    norm = cv2.resize(gray, (640, round(640 * h / w))) if w != 640 else gray
    blur_var = float(cv2.Laplacian(norm, cv2.CV_64F).var())
    brightness = float(gray.mean())
    contrast = float(gray.std())

    label, guidance = "acceptable", None
    if min(h, w) < 200:
        label, guidance = "too_small", "move_closer"
    elif brightness < settings.min_brightness:
        label, guidance = "too_dark", "improve_lighting"
    elif brightness > settings.max_brightness:
        label, guidance = "too_bright", "reduce_glare"
    elif contrast < 12:
        label, guidance = "low_contrast", "improve_lighting"
    elif blur_var < settings.min_blur_variance:
        label, guidance = "blurry", "hold_steady"

    return QualityResult(
        image_quality=label,
        acceptable=label == "acceptable",
        blur_variance=round(blur_var, 2),
        brightness=round(brightness, 2),
        contrast=round(contrast, 2),
        width=w,
        height=h,
        guidance=guidance,
    )
