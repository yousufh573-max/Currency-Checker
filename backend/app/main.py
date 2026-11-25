"""Banknote Assistant API — FastAPI application factory.

Run:  uvicorn app.main:app --host 0.0.0.0 --port 8000
Docs: http://localhost:8000/docs (Swagger UI)
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address

from app.api.deps import Services
from app.api.routes import router, v1
from app.core.config import Settings, get_settings
from app.models.db import Database
from app.services.analyzer import Analyzer
from app.services.classifier import BanknoteClassifier
from app.services.session_service import SessionService

API_VERSION = "1.0.0"


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(level=settings.log_level, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    log = logging.getLogger("banknote")
    if settings.demo_mode and settings.is_production:
        raise RuntimeError("DEMO_MODE must not be enabled in production.")

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        db = Database(settings.database_path)
        classifier = BanknoteClassifier(settings)
        app.state.services = Services(
            settings=settings, classifier=classifier, analyzer=Analyzer(settings, classifier),
            sessions=SessionService(db, settings.analysis_ttl_s),
        )
        if settings.demo_mode:
            log.warning("DEMO MODE ENABLED — recognition results are scripted, not real.")
        yield
        db.close()

    app = FastAPI(
        title="Banknote Assistant API",
        version=API_VERSION,
        description="Bangladeshi banknote analysis (quality, torn ratio, denomination) and cash-counting sessions. "
        "Calculates amounts only; it does not verify authenticity or process payments.",
        lifespan=lifespan,
    )

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware, allow_origins=[o.strip() for o in settings.cors_origins.split(",") if o.strip()],
            allow_methods=["GET", "POST", "DELETE"], allow_headers=["Content-Type"],
        )

    limiter = Limiter(
        key_func=get_remote_address, default_limits=[settings.rate_limit], enabled=settings.is_production
    )
    app.state.limiter = limiter
    app.add_middleware(SlowAPIMiddleware)

    @app.exception_handler(RateLimitExceeded)
    async def _rate_limited(_: Request, exc: RateLimitExceeded):
        return JSONResponse(status_code=429, content={"detail": {"code": "rate_limited", "message": str(exc.detail)}})

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception):
        log.exception("Unhandled error")
        return JSONResponse(status_code=500, content={"detail": {"code": "internal_error", "message": "Internal error."}})

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    app.include_router(router)
    app.include_router(v1)
    return app


app = create_app()
