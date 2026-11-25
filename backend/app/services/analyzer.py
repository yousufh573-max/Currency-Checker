"""Orchestrates the four analysis stages and decides counting eligibility."""
from __future__ import annotations

import itertools
import logging
import threading
import time

import numpy as np

from app.core.config import NOTE_DIMENSIONS_MM, Settings
from app.schemas.analysis import AnalysisResult, BoundingBox, Stage
from app.services.classifier import BanknoteClassifier, ModelNotAvailable
from app.services.quality import assess_quality
from app.services.torn import analyze_torn

log = logging.getLogger(__name__)

# Scripted, clearly-labelled demo results (DEMO_MODE only). The sequence
# mirrors the acceptance scenario: 20 good, 100 good, 500 too torn.
_DEMO_SEQUENCE = [(20, 0.986, 2.0), (100, 0.972, 3.5), (500, 0.916, 40.0)]


def classify_condition(torn_ratio: float | None, reliable: bool, s: Settings) -> str:
    if torn_ratio is None or not reliable:
        return "uncertain"
    if torn_ratio <= s.torn_good_max:
        return "good"
    if torn_ratio <= s.torn_damaged_max:
        return "damaged"
    return "too_torn"


def decide_eligibility(
    *, denomination: int | None, confidence: float | None, condition: str, quality_ok: bool, flags: list[str], s: Settings
) -> tuple[bool, str | None]:
    """Single source of truth for whether a note is added to the total."""
    if not quality_ok:
        return False, "poor_image_quality"
    if "multiple_notes" in flags:
        return False, "multiple_notes"
    if denomination is None:
        return False, "not_recognized"
    if confidence is None or confidence < s.min_confidence:
        return False, "low_confidence"
    if condition == "uncertain":
        return False, "condition_uncertain"
    if condition == "too_torn":
        return False, "too_torn"
    if condition == "damaged" and not s.count_damaged_notes:
        return False, "damaged"
    return True, None


class Analyzer:
    def __init__(self, settings: Settings, classifier: BanknoteClassifier):
        self.s = settings
        self.classifier = classifier
        self._demo_iter = itertools.cycle(_DEMO_SEQUENCE)
        self._demo_lock = threading.Lock()

    def analyze(self, img: np.ndarray) -> AnalysisResult:
        t0 = time.perf_counter()
        res = AnalysisResult(success=False)
        stages: list[Stage] = res.stages  # same list object (pydantic copies constructor args)

        # Stage 1: image quality
        q = assess_quality(img, self.s)
        res.image_quality = q.image_quality
        stages.append(Stage(name="image_quality", status="passed" if q.acceptable else "failed", detail=q.image_quality))
        if not q.acceptable:
            res.rejection_reason = "poor_image_quality"
            res.flags.append(q.guidance or "rescan")
            return self._finish(res, t0)

        # Stage 2: torn detection (segmentation)
        torn = analyze_torn(img)
        if not torn.found:
            stages.append(Stage(name="torn_detection", status="failed", detail=torn.reason or "no_note_found"))
            res.rejection_reason = torn.reason or "no_note_found"
            res.flags.extend(torn.flags)
            return self._finish(res, t0)
        res.flags.extend(torn.flags)
        if torn.bbox:
            res.bounding_box = BoundingBox(x=torn.bbox[0], y=torn.bbox[1], width=torn.bbox[2], height=torn.bbox[3])
        stages.append(
            Stage(name="torn_detection", status="passed" if torn.reliable else "warning", detail=",".join(torn.flags) or "segmented")
        )

        # Stage 4 (recognition) runs before the final ratio so the expected
        # geometry can use the recognised denomination's aspect ratio.
        crop = torn.rectified if torn.rectified is not None else img
        demo = self.s.demo_mode
        try:
            if demo:
                with self._demo_lock:
                    denom, conf, demo_torn = next(self._demo_iter)
                side, version = None, "demo"
            else:
                pred = self.classifier.predict(crop)
                denom, conf, side, version = pred.denomination, pred.confidence, pred.side, self.classifier.model_version
        except ModelNotAvailable as exc:
            stages.append(Stage(name="torn_ratio", status="skipped", detail="awaiting recognition"))
            stages.append(Stage(name="currency_recognition", status="failed", detail="model_not_installed"))
            res.error = "model_not_installed"
            res.rejection_reason = "model_not_installed"
            log.warning("Analysis requested but no model: %s", exc)
            return self._finish(res, t0)

        # Stage 3: torn ratio, refined with denomination-specific geometry
        if demo:
            ratio, reliable = demo_torn, True
        else:
            ratio, reliable = torn.torn_ratio, torn.reliable
            if denom in NOTE_DIMENSIONS_MM:
                L, S = NOTE_DIMENSIONS_MM[denom]
                refined = analyze_torn(img, expected_aspect=L / S)
                if refined.found and refined.torn_ratio is not None:
                    ratio, reliable = refined.torn_ratio, refined.reliable
                    for f in refined.flags:
                        if f not in res.flags:
                            res.flags.append(f)
        res.torn_ratio, res.torn_ratio_reliable = ratio, reliable
        stages.append(
            Stage(name="torn_ratio", status="passed" if reliable else "warning", detail=f"{ratio}%" if ratio is not None else "unknown")
        )

        res.denomination, res.confidence, res.side = denom, round(float(conf), 4), side
        res.model_version, res.demo = version, demo
        recog_ok = denom is not None and conf >= self.s.min_confidence
        stages.append(
            Stage(
                name="currency_recognition",
                status="passed" if recog_ok else "failed",
                detail=(f"{denom} BDT" if denom else "not_a_banknote") + (" (DEMO)" if demo else ""),
            )
        )

        res.condition = classify_condition(ratio, reliable, self.s)
        res.eligible_for_counting, res.rejection_reason = decide_eligibility(
            denomination=denom, confidence=conf, condition=res.condition, quality_ok=True, flags=res.flags, s=self.s
        )
        res.success = True
        return self._finish(res, t0)

    @staticmethod
    def _finish(res: AnalysisResult, t0: float) -> AnalysisResult:
        res.processing_time_ms = int((time.perf_counter() - t0) * 1000)
        return res
