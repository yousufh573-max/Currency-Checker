"""Shared dependencies: service container, upload reading, timeouts."""
from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Callable, TypeVar

from fastapi import HTTPException, Request, UploadFile
from starlette.concurrency import run_in_threadpool

from app.core.config import Settings
from app.services.analyzer import Analyzer
from app.services.classifier import BanknoteClassifier
from app.services.image_io import ImageValidationError, decode_image
from app.services.session_service import SessionService

T = TypeVar("T")


@dataclass
class Services:
    settings: Settings
    classifier: BanknoteClassifier
    analyzer: Analyzer
    sessions: SessionService


def get_services(request: Request) -> Services:
    return request.app.state.services


async def read_image(file: UploadFile, s: Settings):
    # Read at most max+1 bytes so oversized uploads are rejected without buffering them fully.
    data = await file.read(s.max_upload_bytes + 1)
    try:
        return await run_in_threadpool(decode_image, data, max_bytes=s.max_upload_bytes, max_side=s.max_image_side)
    except ImageValidationError as exc:
        status = 413 if exc.code == "file_too_large" else 415 if exc.code == "unsupported_type" else 422
        raise HTTPException(status_code=status, detail={"code": exc.code, "message": str(exc)}) from exc


async def run_with_timeout(fn: Callable[..., T], *args, timeout: float) -> T:
    try:
        return await asyncio.wait_for(run_in_threadpool(fn, *args), timeout=timeout)
    except asyncio.TimeoutError as exc:
        raise HTTPException(status_code=504, detail={"code": "processing_timeout", "message": "Analysis took too long."}) from exc
