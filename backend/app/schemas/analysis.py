"""Pydantic schemas for image quality and banknote analysis."""
from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field

QualityLabel = Literal["acceptable", "blurry", "too_dark", "too_bright", "too_small", "low_contrast"]
Condition = Literal["good", "damaged", "too_torn", "uncertain"]
StageStatus = Literal["passed", "failed", "warning", "skipped"]


class QualityResult(BaseModel):
    image_quality: QualityLabel
    acceptable: bool
    blur_variance: float
    brightness: float
    contrast: float
    width: int
    height: int
    guidance: Optional[str] = Field(None, description="Spoken guidance key, e.g. 'improve_lighting'")


class BoundingBox(BaseModel):
    x: int
    y: int
    width: int
    height: int


class Stage(BaseModel):
    name: Literal["image_quality", "torn_detection", "torn_ratio", "currency_recognition"]
    status: StageStatus
    detail: str = ""


class AnalysisResult(BaseModel):
    success: bool
    analysis_id: Optional[str] = None
    currency: str = "BDT"
    denomination: Optional[int] = None
    side: Optional[str] = None
    confidence: Optional[float] = None
    torn_ratio: Optional[float] = None
    torn_ratio_reliable: bool = False
    condition: Condition = "uncertain"
    image_quality: QualityLabel = "acceptable"
    bounding_box: Optional[BoundingBox] = None
    flags: list[str] = Field(default_factory=list, description="e.g. multiple_notes, possible_fold, occlusion")
    eligible_for_counting: bool = False
    rejection_reason: Optional[str] = None
    stages: list[Stage] = Field(default_factory=list)
    processing_time_ms: int = 0
    model_version: Optional[str] = None
    demo: bool = False
    error: Optional[str] = None


class ModelStatus(BaseModel):
    loaded: bool
    model_version: Optional[str]
    model_path: str
    labels: list[str]
    demo_mode: bool
    message: str
    thresholds: dict[str, float | bool]
