"""Application configuration loaded from environment variables / .env."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]

# Approximate physical sizes (mm) of current-series Bangladeshi banknotes.
# These are used only to derive the *expected aspect ratio* for torn-area
# estimation. Verify against official Bangladesh Bank specifications before
# relying on them; they can be overridden here without code changes.
NOTE_DIMENSIONS_MM: dict[int, tuple[float, float]] = {
    2: (110.0, 60.0),
    5: (120.0, 60.0),
    10: (122.0, 60.0),
    20: (127.0, 60.0),
    50: (130.0, 60.0),
    100: (140.0, 62.0),
    200: (145.0, 64.0),
    500: (152.0, 65.0),
    1000: (160.0, 70.0),
}
SUPPORTED_DENOMINATIONS = tuple(sorted(NOTE_DIMENSIONS_MM))


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BACKEND_DIR / ".env", extra="ignore")

    app_env: str = Field("development", pattern="^(development|production|test)$")
    log_level: str = "INFO"
    cors_origins: str = ""

    model_path: Path = BACKEND_DIR.parent / "machine_learning/weights/banknote_classifier.onnx"
    model_labels_path: Path = BACKEND_DIR.parent / "machine_learning/weights/labels.json"
    model_input_size: int = Field(224, ge=64, le=1024)

    demo_mode: bool = False

    min_confidence: float = Field(0.85, ge=0.0, le=1.0)
    torn_good_max: float = Field(5.0, ge=0.0, le=100.0)
    torn_damaged_max: float = Field(20.0, ge=0.0, le=100.0)
    count_damaged_notes: bool = True

    min_blur_variance: float = 60.0
    min_brightness: float = 45.0
    max_brightness: float = 225.0

    max_upload_bytes: int = Field(6_000_000, ge=10_000, le=50_000_000)
    max_image_side: int = Field(4096, ge=256, le=12000)
    request_timeout_s: float = Field(20.0, gt=0)
    rate_limit: str = "60/minute"

    database_path: Path = BACKEND_DIR / "data/banknote_assistant.db"
    analysis_ttl_s: int = Field(900, ge=10)

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
