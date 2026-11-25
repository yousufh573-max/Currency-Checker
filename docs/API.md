# Banknote Assistant API (v1)

Interactive Swagger docs: `http://<host>:8000/docs` · OpenAPI JSON: `/openapi.json`.

All errors use `{"detail": {"code": "...", "message": "..."}}`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness + whether a model is loaded / demo mode |
| GET | `/api/v1/model/status` | Model version, labels, thresholds, human-readable status |
| POST | `/api/v1/image/quality` | Multipart `image` → blur / brightness / contrast verdict + guidance key |
| POST | `/api/v1/banknote/analyze` | Multipart `image` → full analysis (4 stages) + `analysis_id` |
| POST | `/api/v1/session/create` | New counting session |
| GET | `/api/v1/session/{id}` | Session state: totals, denomination counts, scans |
| POST | `/api/v1/session/{id}/scan` | `{"analysis_id", "idempotency_key"}` → record a scan |
| POST | `/api/v1/session/{id}/undo` | Remove the last scan |
| POST | `/api/v1/session/{id}/calculate` | `{"required_amount": 70}` → remaining / shortage |
| POST | `/api/v1/session/{id}/complete` | Freeze and save the session |
| DELETE | `/api/v1/session/{id}` | Delete session and its scans |

## Analyze response

```json
{
  "success": true,
  "analysis_id": "0c6b…",
  "currency": "BDT",
  "denomination": 20,
  "side": "back",
  "confidence": 0.986,
  "torn_ratio": 2.0,
  "torn_ratio_reliable": true,
  "condition": "good",
  "image_quality": "acceptable",
  "bounding_box": {"x": 198, "y": 208, "width": 604, "height": 284},
  "flags": [],
  "eligible_for_counting": true,
  "rejection_reason": null,
  "stages": [
    {"name": "image_quality", "status": "passed", "detail": "acceptable"},
    {"name": "torn_detection", "status": "passed", "detail": "segmented"},
    {"name": "torn_ratio", "status": "passed", "detail": "2.0%"},
    {"name": "currency_recognition", "status": "passed", "detail": "20 BDT"}
  ],
  "processing_time_ms": 450,
  "model_version": "1.0.0",
  "demo": false,
  "error": null
}
```

(Example values only.) Without a model: `success:false`, `error:"model_not_installed"`, recognition stage `failed`.

`condition`: `good` (≤ TORN_GOOD_MAX %), `damaged` (≤ TORN_DAMAGED_MAX %), `too_torn`, or
`uncertain` (geometry unreliable: note cut off by frame, multiple notes, finger occlusion,
possible fold, busy background). `flags` explains why.

`rejection_reason`: `poor_image_quality`, `no_note_found`, `multiple_notes`, `not_recognized`,
`low_confidence`, `condition_uncertain`, `too_torn`, `damaged` (if damaged notes are not counted),
`model_not_installed`.

## Counting rules

* Scans reference a server-side `analysis_id` (valid `ANALYSIS_TTL_S`), so clients cannot submit
  arbitrary denominations.
* Same `idempotency_key` → original result returned with `"duplicate": true` (safe retries).
* Same `analysis_id` with a new key → `409 analysis_already_used` (repeated camera frames).
* Different captures of the same denomination are separate notes and are both counted.
* Only `eligible_for_counting` analyses add to `total_accepted`; others are kept as rejected scans.

## Validation & limits

* Image type checked by magic bytes (JPEG/PNG/WEBP); `MAX_UPLOAD_BYTES` (413), `MAX_IMAGE_SIDE`.
* Images are decoded in memory and never written to disk; only numeric results are stored.
* `REQUEST_TIMEOUT_S` → 504 `processing_timeout`.
* Rate limiting (`RATE_LIMIT`, default 60/minute per IP) when `APP_ENV=production`.
* `DEMO_MODE=true` is refused when `APP_ENV=production`.
