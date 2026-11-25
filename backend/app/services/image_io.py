"""Safe image decoding and validation.

Uploaded bytes are validated by *magic number* (not by the client-supplied
content type or filename), size-limited, and decoded in memory. Nothing is
written to disk, so there are no temporary images to clean up.
"""
from __future__ import annotations

import cv2
import numpy as np

JPEG_MAGIC = b"\xff\xd8\xff"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
WEBP_RIFF = b"RIFF"

# Images are downscaled to this longest side before analysis: enough detail
# for segmentation/classification while bounding CPU and memory use.
ANALYSIS_MAX_SIDE = 1024


class ImageValidationError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def sniff_format(data: bytes) -> str | None:
    if data.startswith(JPEG_MAGIC):
        return "jpeg"
    if data.startswith(PNG_MAGIC):
        return "png"
    if data[:4] == WEBP_RIFF and data[8:12] == b"WEBP":
        return "webp"
    return None


def decode_image(data: bytes, *, max_bytes: int, max_side: int) -> np.ndarray:
    """Validate and decode an uploaded image into a BGR array (downscaled)."""
    if not data:
        raise ImageValidationError("empty_file", "No image data received.")
    if len(data) > max_bytes:
        raise ImageValidationError("file_too_large", f"Image exceeds {max_bytes} bytes.")
    if sniff_format(data) is None:
        raise ImageValidationError("unsupported_type", "Only JPEG, PNG or WEBP images are accepted.")

    buf = np.frombuffer(data, dtype=np.uint8)
    # Check dimensions cheaply first to avoid decompression bombs.
    img = cv2.imdecode(buf, cv2.IMREAD_REDUCED_COLOR_2) if len(data) > 3_000_000 else None
    if img is None:
        img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise ImageValidationError("decode_failed", "The image could not be decoded.")
    h, w = img.shape[:2]
    if max(h, w) > max_side:
        raise ImageValidationError("image_too_large", f"Image dimensions exceed {max_side}px.")
    if min(h, w) < 64:
        raise ImageValidationError("image_too_small", "Image is too small to analyse.")

    scale = ANALYSIS_MAX_SIDE / max(h, w)
    if scale < 1.0:
        img = cv2.resize(img, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA)
    return img
