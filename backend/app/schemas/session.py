"""Pydantic schemas for counting sessions."""
from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field


class ScanRequest(BaseModel):
    analysis_id: str = Field(..., min_length=8, max_length=64, pattern=r"^[A-Za-z0-9\-]+$")
    idempotency_key: str = Field(..., min_length=8, max_length=64, pattern=r"^[A-Za-z0-9\-]+$")


class ScanRecord(BaseModel):
    scan_id: str
    denomination: Optional[int]
    confidence: Optional[float]
    torn_ratio: Optional[float]
    condition: str
    accepted: bool
    rejection_reason: Optional[str]
    created_at: str


class SessionState(BaseModel):
    id: str
    status: Literal["active", "completed"]
    total_accepted: int
    accepted_count: int
    rejected_count: int
    denomination_counts: dict[str, int]
    required_amount: Optional[int]
    remaining: Optional[int]
    shortage: Optional[int]
    scans: list[ScanRecord]
    created_at: str
    completed_at: Optional[str]


class ScanResponse(BaseModel):
    scan: ScanRecord
    duplicate: bool = Field(False, description="True when the idempotency key was already processed")
    session: SessionState


class CalculateRequest(BaseModel):
    required_amount: int = Field(..., ge=0, le=10_000_000)


class CalculateResponse(BaseModel):
    total_accepted: int
    required_amount: int
    remaining: int
    shortage: int
    sufficient: bool
