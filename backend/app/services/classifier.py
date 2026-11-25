"""Denomination classifier.

Loads an ONNX image-classification model exported by
``machine_learning/export/export_model.py`` and runs it with OpenCV DNN (no
PyTorch needed at serving time). The companion ``labels.json`` describes the
classes, e.g.::

    {"model_version": "1.0.0", "input_size": 224,
     "mean": [0.0, 0.0, 0.0], "std": [1.0, 1.0, 1.0],
     "labels": ["2_front", "2_back", ..., "1000_back", "not_banknote"]}

If the model is missing, ``status()`` says so and ``predict()`` raises
``ModelNotAvailable`` — recognition is never faked.
"""
from __future__ import annotations

import json
import logging
import threading
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

from app.core.config import SUPPORTED_DENOMINATIONS, Settings

log = logging.getLogger(__name__)


class ModelNotAvailable(RuntimeError):
    pass


@dataclass
class Prediction:
    denomination: int | None  # None => not a banknote / unknown class
    side: str | None
    confidence: float
    label: str
    top3: list[tuple[str, float]]


def parse_label(label: str) -> tuple[int | None, str | None]:
    head, _, side = label.partition("_")
    if head.isdigit() and int(head) in SUPPORTED_DENOMINATIONS:
        return int(head), (side or None)
    return None, None


class BanknoteClassifier:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._net = None
        self._labels: list[str] = []
        self._meta: dict = {}
        self._error: str | None = None
        self._lock = threading.Lock()  # cv2.dnn.Net is not thread-safe
        self.load()

    # ------------------------------------------------------------------ load
    def load(self) -> None:
        mp, lp = Path(self.settings.model_path), Path(self.settings.model_labels_path)
        self._net, self._error = None, None
        if not mp.is_file():
            self._error = f"Model file not found at {mp}. Train and export a model (see machine_learning/README.md)."
            log.warning(self._error)
            return
        if not lp.is_file():
            self._error = f"Labels file not found at {lp}."
            log.warning(self._error)
            return
        try:
            self._meta = json.loads(lp.read_text(encoding="utf-8"))
            self._labels = list(self._meta["labels"])
            self._net = cv2.dnn.readNetFromONNX(str(mp))
            log.info("Loaded classifier %s with %d classes", self.model_version, len(self._labels))
        except Exception as exc:  # noqa: BLE001 - report any load failure
            self._error = f"Failed to load model: {exc}"
            self._net = None
            log.exception("Model load failed")

    @property
    def loaded(self) -> bool:
        return self._net is not None

    @property
    def model_version(self) -> str | None:
        return self._meta.get("model_version") if self.loaded else None

    @property
    def labels(self) -> list[str]:
        return self._labels

    @property
    def error(self) -> str | None:
        return self._error

    # --------------------------------------------------------------- predict
    def _preprocess(self, bgr: np.ndarray) -> np.ndarray:
        size = int(self._meta.get("input_size", self.settings.model_input_size))
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        # Letterbox to a square to keep the note's aspect ratio.
        h, w = rgb.shape[:2]
        s = size / max(h, w)
        resized = cv2.resize(rgb, (max(1, round(w * s)), max(1, round(h * s))), interpolation=cv2.INTER_AREA)
        canvas = np.full((size, size, 3), 114, np.uint8)
        y0, x0 = (size - resized.shape[0]) // 2, (size - resized.shape[1]) // 2
        canvas[y0 : y0 + resized.shape[0], x0 : x0 + resized.shape[1]] = resized
        x = canvas.astype(np.float32) / 255.0
        mean = np.array(self._meta.get("mean", [0, 0, 0]), np.float32)
        std = np.array(self._meta.get("std", [1, 1, 1]), np.float32)
        x = (x - mean) / std
        return x.transpose(2, 0, 1)[None]  # NCHW

    def predict(self, bgr: np.ndarray) -> Prediction:
        if not self.loaded:
            raise ModelNotAvailable(self._error or "Model not loaded")
        blob = self._preprocess(bgr)
        with self._lock:
            self._net.setInput(blob)
            out = self._net.forward().reshape(-1).astype(np.float64)
        if out.min() < 0 or abs(out.sum() - 1.0) > 1e-3:  # logits -> softmax
            e = np.exp(out - out.max())
            out = e / e.sum()
        order = np.argsort(out)[::-1]
        top = [(self._labels[i], float(out[i])) for i in order[:3]]
        label, conf = top[0]
        denom, side = parse_label(label)
        return Prediction(denomination=denom, side=side, confidence=conf, label=label, top3=top)
