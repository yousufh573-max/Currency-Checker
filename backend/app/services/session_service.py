"""Session-based amount calculation with idempotent scan submission.

Rules
-----
* A scan references a server-side ``analysis_id``; the client cannot submit
  its own denomination, so totals always reflect real analysis results.
* The same ``idempotency_key`` returns the original result (API retries).
* The same ``analysis_id`` can only be consumed once (repeated frames).
* Two different captures of the same denomination are *not* duplicates.
* Only eligible analyses are added to the accepted total.
"""
from __future__ import annotations

import time
import uuid
from datetime import datetime, timezone

from app.models.db import Database
from app.schemas.analysis import AnalysisResult
from app.schemas.session import CalculateResponse, ScanRecord, ScanResponse, SessionState


class SessionError(Exception):
    def __init__(self, code: str, message: str, status: int = 400):
        super().__init__(message)
        self.code, self.status = code, status


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def compute_payment(total: int, required: int) -> CalculateResponse:
    diff = total - required
    return CalculateResponse(
        total_accepted=total, required_amount=required, remaining=max(diff, 0), shortage=max(-diff, 0), sufficient=diff >= 0
    )


class SessionService:
    def __init__(self, db: Database, analysis_ttl_s: int):
        self.db = db
        self.ttl = analysis_ttl_s

    # ------------------------------------------------------------ analyses
    def record_analysis(self, res: AnalysisResult) -> str:
        aid = str(uuid.uuid4())
        with self.db.tx() as c:
            c.execute("DELETE FROM analyses WHERE created_at < ?", (time.time() - self.ttl,))
            c.execute(
                "INSERT INTO analyses (id, denomination, confidence, torn_ratio, condition, eligible, rejection_reason, demo, created_at)"
                " VALUES (?,?,?,?,?,?,?,?,?)",
                (aid, res.denomination, res.confidence, res.torn_ratio, res.condition, int(res.eligible_for_counting),
                 res.rejection_reason, int(res.demo), time.time()),
            )
        return aid

    # ------------------------------------------------------------ sessions
    def create(self) -> SessionState:
        sid = str(uuid.uuid4())
        with self.db.tx() as c:
            c.execute("INSERT INTO sessions (id, created_at) VALUES (?, ?)", (sid, _now()))
        return self.get(sid)

    def _row(self, sid: str):
        rows = self.db.query("SELECT * FROM sessions WHERE id = ?", (sid,))
        if not rows:
            raise SessionError("session_not_found", "Session not found.", 404)
        return rows[0]

    def get(self, sid: str) -> SessionState:
        s = self._row(sid)
        scans = self.db.query("SELECT * FROM scans WHERE session_id = ? AND undone = 0 ORDER BY seq", (sid,))
        records = [
            ScanRecord(scan_id=r["scan_id"], denomination=r["denomination"], confidence=r["confidence"], torn_ratio=r["torn_ratio"],
                       condition=r["condition"], accepted=bool(r["accepted"]), rejection_reason=r["rejection_reason"],
                       created_at=r["created_at"])
            for r in scans
        ]
        accepted = [r for r in records if r.accepted]
        total = sum(r.denomination or 0 for r in accepted)
        counts: dict[str, int] = {}
        for r in accepted:
            counts[str(r.denomination)] = counts.get(str(r.denomination), 0) + 1
        req = s["required_amount"]
        pay = compute_payment(total, req) if req is not None else None
        return SessionState(
            id=sid, status=s["status"], total_accepted=total, accepted_count=len(accepted),
            rejected_count=len(records) - len(accepted), denomination_counts=counts, required_amount=req,
            remaining=pay.remaining if pay else None, shortage=pay.shortage if pay else None, scans=records,
            created_at=s["created_at"], completed_at=s["completed_at"],
        )

    def _require_active(self, sid: str) -> None:
        if self._row(sid)["status"] != "active":
            raise SessionError("session_completed", "Session is already completed.", 409)

    def add_scan(self, sid: str, analysis_id: str, idem_key: str) -> ScanResponse:
        self._require_active(sid)
        with self.db.tx() as c:
            prev = c.execute("SELECT scan_id FROM scans WHERE session_id=? AND idempotency_key=?", (sid, idem_key)).fetchone()
            if prev:
                duplicate_scan_id = prev["scan_id"]
            else:
                duplicate_scan_id = None
                a = c.execute("SELECT * FROM analyses WHERE id = ?", (analysis_id,)).fetchone()
                if a is None or a["created_at"] < time.time() - self.ttl:
                    raise SessionError("analysis_not_found", "Analysis not found or expired. Please rescan.", 404)
                if a["consumed"]:
                    raise SessionError("analysis_already_used", "This capture was already counted.", 409)
                c.execute("UPDATE analyses SET consumed = 1 WHERE id = ?", (analysis_id,))
                seq = c.execute("SELECT COALESCE(MAX(seq), 0) + 1 FROM scans WHERE session_id=?", (sid,)).fetchone()[0]
                scan_id = str(uuid.uuid4())
                c.execute(
                    "INSERT INTO scans (scan_id, session_id, idempotency_key, analysis_id, denomination, confidence, torn_ratio,"
                    " condition, accepted, rejection_reason, seq, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    (scan_id, sid, idem_key, analysis_id, a["denomination"], a["confidence"], a["torn_ratio"], a["condition"],
                     a["eligible"], a["rejection_reason"], seq, _now()),
                )
        state = self.get(sid)
        target = duplicate_scan_id or scan_id
        rec = next((r for r in state.scans if r.scan_id == target), None)
        if rec is None:  # was undone after the original request
            raise SessionError("scan_undone", "This scan was undone.", 409)
        return ScanResponse(scan=rec, duplicate=duplicate_scan_id is not None, session=state)

    def undo(self, sid: str) -> SessionState:
        self._require_active(sid)
        with self.db.tx() as c:
            last = c.execute("SELECT scan_id FROM scans WHERE session_id=? AND undone=0 ORDER BY seq DESC LIMIT 1", (sid,)).fetchone()
            if last is None:
                raise SessionError("nothing_to_undo", "There is no scan to undo.", 409)
            c.execute("UPDATE scans SET undone = 1 WHERE scan_id = ?", (last["scan_id"],))
        return self.get(sid)

    def calculate(self, sid: str, required: int) -> CalculateResponse:
        self._row(sid)
        with self.db.tx() as c:
            c.execute("UPDATE sessions SET required_amount = ? WHERE id = ?", (required, sid))
        return compute_payment(self.get(sid).total_accepted, required)

    def complete(self, sid: str) -> SessionState:
        self._require_active(sid)
        with self.db.tx() as c:
            c.execute("UPDATE sessions SET status='completed', completed_at=? WHERE id=?", (_now(), sid))
        return self.get(sid)

    def delete(self, sid: str) -> None:
        self._row(sid)
        with self.db.tx() as c:
            c.execute("DELETE FROM scans WHERE session_id = ?", (sid,))
            c.execute("DELETE FROM sessions WHERE id = ?", (sid,))
