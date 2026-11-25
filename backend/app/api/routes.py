"""HTTP routes."""
from __future__ import annotations

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.api.deps import Services, get_services, read_image, run_with_timeout
from app.schemas.analysis import AnalysisResult, ModelStatus, QualityResult
from app.schemas.session import CalculateRequest, CalculateResponse, ScanRequest, ScanResponse, SessionState
from app.services.quality import assess_quality
from app.services.session_service import SessionError

router = APIRouter()
v1 = APIRouter(prefix="/api/v1")


def _session_call(fn, *args):
    try:
        return fn(*args)
    except SessionError as exc:
        raise HTTPException(status_code=exc.status, detail={"code": exc.code, "message": str(exc)}) from exc


@router.get("/health", tags=["system"])
def health(svc: Services = Depends(get_services)):
    return {"status": "ok", "model_loaded": svc.classifier.loaded, "demo_mode": svc.settings.demo_mode}


@v1.get("/model/status", response_model=ModelStatus, tags=["model"])
def model_status(svc: Services = Depends(get_services)):
    s, c = svc.settings, svc.classifier
    if s.demo_mode:
        msg = "DEMO MODE: results are scripted and are NOT real banknote recognition."
    elif c.loaded:
        msg = "Model loaded."
    else:
        msg = c.error or "Model not loaded."
    return ModelStatus(
        loaded=c.loaded, model_version=c.model_version, model_path=str(s.model_path), labels=c.labels, demo_mode=s.demo_mode,
        message=msg,
        thresholds={"min_confidence": s.min_confidence, "torn_good_max": s.torn_good_max,
                    "torn_damaged_max": s.torn_damaged_max, "count_damaged_notes": s.count_damaged_notes},
    )


@v1.post("/image/quality", response_model=QualityResult, tags=["analysis"])
async def image_quality(image: UploadFile = File(...), svc: Services = Depends(get_services)):
    img = await read_image(image, svc.settings)
    return await run_with_timeout(assess_quality, img, svc.settings, timeout=svc.settings.request_timeout_s)


@v1.post("/banknote/analyze", response_model=AnalysisResult, tags=["analysis"])
async def analyze(image: UploadFile = File(...), svc: Services = Depends(get_services)):
    """Run quality → segmentation/torn → recognition. The image is processed
    in memory and discarded; only the numeric result is kept (for scan submission)."""
    img = await read_image(image, svc.settings)
    res = await run_with_timeout(svc.analyzer.analyze, img, timeout=svc.settings.request_timeout_s)
    if res.success:
        res.analysis_id = svc.sessions.record_analysis(res)
    return res


@v1.post("/session/create", response_model=SessionState, status_code=201, tags=["session"])
def create_session(svc: Services = Depends(get_services)):
    return svc.sessions.create()


@v1.get("/session/{session_id}", response_model=SessionState, tags=["session"])
def get_session(session_id: str, svc: Services = Depends(get_services)):
    return _session_call(svc.sessions.get, session_id)


@v1.post("/session/{session_id}/scan", response_model=ScanResponse, tags=["session"])
def add_scan(session_id: str, body: ScanRequest, svc: Services = Depends(get_services)):
    return _session_call(svc.sessions.add_scan, session_id, body.analysis_id, body.idempotency_key)


@v1.post("/session/{session_id}/undo", response_model=SessionState, tags=["session"])
def undo(session_id: str, svc: Services = Depends(get_services)):
    return _session_call(svc.sessions.undo, session_id)


@v1.post("/session/{session_id}/calculate", response_model=CalculateResponse, tags=["session"])
def calculate(session_id: str, body: CalculateRequest, svc: Services = Depends(get_services)):
    return _session_call(svc.sessions.calculate, session_id, body.required_amount)


@v1.post("/session/{session_id}/complete", response_model=SessionState, tags=["session"])
def complete(session_id: str, svc: Services = Depends(get_services)):
    return _session_call(svc.sessions.complete, session_id)


@v1.delete("/session/{session_id}", status_code=204, tags=["session"])
def delete_session(session_id: str, svc: Services = Depends(get_services)):
    _session_call(svc.sessions.delete, session_id)
