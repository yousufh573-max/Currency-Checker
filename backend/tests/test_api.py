"""API tests. Recognition is exercised with a stub classifier (no trained model
exists in the repository); the stub is injected only in tests."""
import uuid

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app
from app.services.classifier import Prediction
from tests.synth import encode, scene, tear


class StubClassifier:
    """Returns a queued denomination per call — test double only."""

    loaded = True
    model_version = "test-stub"
    labels = ["20_front", "100_front", "500_front", "not_banknote"]
    error = None

    def __init__(self):
        self.queue: list[tuple[int | None, float]] = []

    def predict(self, _img):
        d, c = self.queue.pop(0)
        return Prediction(denomination=d, side="front", confidence=c, label=f"{d}_front", top3=[])


def make_client(tmp_path, **overrides):
    s = Settings(_env_file=None, database_path=tmp_path / "t.db", model_path=tmp_path / "missing.onnx", **overrides)
    return TestClient(create_app(s))


@pytest.fixture
def client(tmp_path):
    with make_client(tmp_path) as c:
        yield c


@pytest.fixture
def stub_client(tmp_path):
    with make_client(tmp_path) as c:
        stub = StubClassifier()
        c.app.state.services.analyzer.classifier = stub
        c.app.state.services.classifier = stub
        yield c, stub


def good_note():
    return encode(scene()[0])


def torn_note(frac=0.40):
    img, mask = scene()
    return encode(tear(img, mask, frac)[0])


def analyze(c, data):
    r = c.post("/api/v1/banknote/analyze", files={"image": ("n.jpg", data, "image/jpeg")})
    assert r.status_code == 200, r.text
    return r.json()


def scan(c, sid, aid, key=None):
    return c.post(f"/api/v1/session/{sid}/scan", json={"analysis_id": aid, "idempotency_key": key or str(uuid.uuid4())})


def test_health_and_model_status_report_missing_model(client):
    assert client.get("/health").json()["model_loaded"] is False
    st = client.get("/api/v1/model/status").json()
    assert st["loaded"] is False and "not found" in st["message"]


def test_analyze_without_model_never_fakes_recognition(client):
    res = analyze(client, good_note())
    assert res["success"] is False
    assert res["error"] == "model_not_installed"
    assert res["denomination"] is None and res["eligible_for_counting"] is False
    assert [s["name"] for s in res["stages"]] == ["image_quality", "torn_detection", "torn_ratio", "currency_recognition"]
    assert res["stages"][-1]["status"] == "failed"


def test_upload_validation(client):
    r = client.post("/api/v1/banknote/analyze", files={"image": ("x.gif", b"GIF89a" + b"0" * 100, "image/gif")})
    assert r.status_code == 415
    r = client.post("/api/v1/image/quality", files={"image": ("n.jpg", good_note(), "image/jpeg")})
    assert r.status_code == 200 and r.json()["acceptable"] is True


def test_upload_too_large(tmp_path):
    with make_client(tmp_path, max_upload_bytes=10_000) as c:
        r = c.post("/api/v1/image/quality", files={"image": ("n.jpg", good_note(), "image/jpeg")})
        assert r.status_code == 413


def test_full_scenario_20_100_torn500_pay70(stub_client):
    c, stub = stub_client
    sid = c.post("/api/v1/session/create").json()["id"]

    stub.queue.append((20, 0.986))
    a1 = analyze(c, good_note())
    assert a1["eligible_for_counting"] and a1["condition"] == "good"
    assert scan(c, sid, a1["analysis_id"]).json()["session"]["total_accepted"] == 20

    stub.queue.append((100, 0.97))
    a2 = analyze(c, encode(scene(seed=5)[0]))
    assert scan(c, sid, a2["analysis_id"]).json()["session"]["total_accepted"] == 120

    stub.queue.append((500, 0.916))
    a3 = analyze(c, torn_note(0.40))
    assert a3["condition"] == "too_torn" and a3["eligible_for_counting"] is False
    assert a3["rejection_reason"] == "too_torn"
    r3 = scan(c, sid, a3["analysis_id"]).json()
    assert r3["scan"]["accepted"] is False
    assert r3["session"]["total_accepted"] == 120
    assert r3["session"]["rejected_count"] == 1
    assert r3["session"]["denomination_counts"] == {"20": 1, "100": 1}

    calc = c.post(f"/api/v1/session/{sid}/calculate", json={"required_amount": 70}).json()
    assert calc == {"total_accepted": 120, "required_amount": 70, "remaining": 50, "shortage": 0, "sufficient": True}

    done = c.post(f"/api/v1/session/{sid}/complete").json()
    assert done["status"] == "completed" and done["remaining"] == 50
    assert scan(c, sid, a1["analysis_id"]).status_code == 409  # completed sessions are frozen


def test_shortage(stub_client):
    c, stub = stub_client
    sid = c.post("/api/v1/session/create").json()["id"]
    stub.queue.append((20, 0.99))
    scan(c, sid, analyze(c, good_note())["analysis_id"])
    calc = c.post(f"/api/v1/session/{sid}/calculate", json={"required_amount": 70}).json()
    assert calc["sufficient"] is False and calc["shortage"] == 50 and calc["remaining"] == 0


def test_idempotency_and_duplicate_prevention(stub_client):
    c, stub = stub_client
    sid = c.post("/api/v1/session/create").json()["id"]
    stub.queue += [(20, 0.99), (20, 0.99)]
    a1 = analyze(c, good_note())["analysis_id"]
    key = str(uuid.uuid4())
    first = scan(c, sid, a1, key).json()
    retry = scan(c, sid, a1, key).json()  # network retry, same key
    assert retry["duplicate"] is True and retry["scan"]["scan_id"] == first["scan"]["scan_id"]
    assert retry["session"]["total_accepted"] == 20
    # Same capture (analysis) with a new key -> rejected as already counted.
    assert scan(c, sid, a1).status_code == 409
    # A different physical note of the same denomination is NOT a duplicate.
    a2 = analyze(c, encode(scene(seed=9)[0]))["analysis_id"]
    assert scan(c, sid, a2).json()["session"]["total_accepted"] == 40


def test_low_confidence_not_counted(stub_client):
    c, stub = stub_client
    sid = c.post("/api/v1/session/create").json()["id"]
    stub.queue.append((1000, 0.40))
    a = analyze(c, good_note())
    assert a["eligible_for_counting"] is False and a["rejection_reason"] == "low_confidence"
    assert scan(c, sid, a["analysis_id"]).json()["session"]["total_accepted"] == 0


def test_forged_analysis_id_rejected(stub_client):
    c, _ = stub_client
    sid = c.post("/api/v1/session/create").json()["id"]
    assert scan(c, sid, str(uuid.uuid4())).status_code == 404
    bad = c.post(f"/api/v1/session/{sid}/scan", json={"analysis_id": "x'; DROP TABLE", "idempotency_key": "abcdefgh"})
    assert bad.status_code == 422


def test_undo_and_delete(stub_client):
    c, stub = stub_client
    sid = c.post("/api/v1/session/create").json()["id"]
    stub.queue += [(20, 0.99), (100, 0.99)]
    scan(c, sid, analyze(c, good_note())["analysis_id"])
    scan(c, sid, analyze(c, encode(scene(seed=3)[0]))["analysis_id"])
    assert c.post(f"/api/v1/session/{sid}/undo").json()["total_accepted"] == 20
    assert c.post(f"/api/v1/session/{sid}/undo").json()["total_accepted"] == 0
    assert c.post(f"/api/v1/session/{sid}/undo").status_code == 409
    assert c.delete(f"/api/v1/session/{sid}").status_code == 204
    assert c.get(f"/api/v1/session/{sid}").status_code == 404


def test_demo_mode_is_labelled(tmp_path):
    with make_client(tmp_path, demo_mode=True) as c:
        assert "DEMO" in c.get("/api/v1/model/status").json()["message"]
        res = analyze(c, good_note())
        assert res["demo"] is True and res["model_version"] == "demo"
        assert "(DEMO)" in res["stages"][-1]["detail"]


def test_demo_mode_forbidden_in_production(tmp_path):
    with pytest.raises(RuntimeError):
        create_app(Settings(_env_file=None, app_env="production", demo_mode=True, database_path=tmp_path / "x.db"))
