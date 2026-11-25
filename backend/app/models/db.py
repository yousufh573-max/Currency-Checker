"""SQLite persistence for analyses and counting sessions.

Only analysis *results* are stored (denomination, confidence, ratio, …) —
never images or serial numbers.
"""
from __future__ import annotations

import sqlite3
import threading
from contextlib import contextmanager
from pathlib import Path

SCHEMA = """
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS analyses (
    id TEXT PRIMARY KEY,
    denomination INTEGER,
    confidence REAL,
    torn_ratio REAL,
    condition TEXT NOT NULL,
    eligible INTEGER NOT NULL,
    rejection_reason TEXT,
    demo INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    consumed INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'active',
    required_amount INTEGER,
    created_at TEXT NOT NULL,
    completed_at TEXT
);
CREATE TABLE IF NOT EXISTS scans (
    scan_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    analysis_id TEXT NOT NULL,
    denomination INTEGER,
    confidence REAL,
    torn_ratio REAL,
    condition TEXT NOT NULL,
    accepted INTEGER NOT NULL,
    rejection_reason TEXT,
    undone INTEGER NOT NULL DEFAULT 0,
    seq INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE(session_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_scans_session ON scans(session_id, seq);
"""


class Database:
    def __init__(self, path: Path | str):
        self.path = str(path)
        if self.path != ":memory:":
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(self.path, check_same_thread=False, isolation_level=None)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._conn.executescript(SCHEMA)
        self._lock = threading.RLock()

    @contextmanager
    def tx(self):
        """Serialised transaction (SQLite has a single writer anyway)."""
        with self._lock:
            self._conn.execute("BEGIN IMMEDIATE")
            try:
                yield self._conn
                self._conn.execute("COMMIT")
            except Exception:
                self._conn.execute("ROLLBACK")
                raise

    def query(self, sql: str, params: tuple = ()) -> list[sqlite3.Row]:
        with self._lock:
            return self._conn.execute(sql, params).fetchall()

    def close(self) -> None:
        self._conn.close()
