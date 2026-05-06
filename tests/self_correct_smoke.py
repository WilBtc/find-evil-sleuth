#!/usr/bin/env python3
"""
tests/self_correct_smoke.py

Acceptance test for 2.3.2: a deliberately-failed tool call triggers exactly
1 retry that succeeds.

Strategy:
 - Insert a synthetic case into Postgres.
 - Mock the Claude subprocess and broker so the first call is a "failure"
   and the retry produces SUCCESS.
 - Call SelfCorrector.attempt() and assert:
     1. Exactly 1 self_corrections row with succeeded=True is written.
     2. The Sleuth.self_correct.attempt obs event was emitted once.
     3. The function returns True.
"""

from __future__ import annotations

import json
import os
import sys
import time
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from adws.self_correct import (
    SelfCorrector,
    build_retry_prompt,
    _pick_strategy,
    MAX_RETRIES,
)

# ---------------------------------------------------------------------------
# Unit tests (no DB, no subprocess)
# ---------------------------------------------------------------------------

class TestStrategyPicker(unittest.TestCase):
    def test_vol3_profile_mismatch(self):
        stderr = "Unsatisfied requirement: volatility3.framework.interfaces.layers.TranslationLayerInterface"
        self.assertEqual(_pick_strategy("vol3", stderr), "derive_profile")

    def test_tshark_truncated(self):
        stderr = "appears to have been cut short in the middle of a packet"
        self.assertEqual(_pick_strategy("tshark", stderr), "editcap_recover")

    def test_unknown_stderr_falls_back_to_adjust_args(self):
        self.assertEqual(_pick_strategy("fls", "error: bad offset"), "adjust_args")

    def test_case_insensitive(self):
        self.assertEqual(_pick_strategy("tshark", "EOF reached"), "editcap_recover")


class TestBuildRetryPrompt(unittest.TestCase):
    def test_prompt_contains_required_sections(self):
        prompt = build_retry_prompt(
            case_id="smoke-001",
            specialist="memory",
            failed_tool="vol3",
            failed_args={"plugin": "windows.malfind"},
            failed_exit=1,
            stderr_tail="Unsatisfied requirement: translation layer",
            attempt_number=1,
            prior_attempts=[],
            strategy="derive_profile",
        )
        self.assertIn("SELF-CORRECTION REQUEST (attempt 1 of", prompt)
        self.assertIn("smoke-001", prompt)
        self.assertIn("vol3", prompt)
        self.assertIn("derive_profile", prompt)
        self.assertIn("RETRY_CALL:", prompt)
        self.assertIn("SUCCESS", prompt)

    def test_prior_attempts_included(self):
        prior = [{"retry_tool": "windows.info", "failed_exit": 1, "succeeded": False}]
        prompt = build_retry_prompt(
            case_id="c1",
            specialist="memory",
            failed_tool="vol3",
            failed_args={},
            failed_exit=1,
            stderr_tail="error",
            attempt_number=2,
            prior_attempts=prior,
            strategy="derive_profile",
        )
        self.assertIn("Prior attempts:", prompt)
        self.assertIn("windows.info", prompt)


# ---------------------------------------------------------------------------
# Integration test — mocked DB + subprocess
# ---------------------------------------------------------------------------

class FakeConn:
    """Minimal psycopg2-like connection backed by in-memory lists."""

    def __init__(self):
        self.rows: list[dict] = []

    def cursor(self, cursor_factory=None):
        return FakeCursor(self)

    @property
    def autocommit(self):
        return True

    @autocommit.setter
    def autocommit(self, _v):
        pass

    def close(self):
        pass


class FakeCursor:
    def __init__(self, conn: FakeConn, cursor_factory=None):
        self._conn = conn
        self._rows: list[dict] = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def execute(self, sql: str, params=None):
        sql_u = sql.strip().upper()
        if sql_u.startswith("INSERT INTO SELF_CORRECTIONS"):
            (case_id, specialist, failed_tool, failed_args_j,
             failed_exit, stderr_tail, strategy,
             retry_tool, retry_args_j, succeeded) = params
            self._conn.rows.append({
                "case_id": case_id,
                "specialist": specialist,
                "failed_tool": failed_tool,
                "failed_args": json.loads(failed_args_j),
                "failed_exit": failed_exit,
                "stderr_tail": stderr_tail,
                "retry_strategy": strategy,
                "retry_tool": retry_tool,
                "retry_args": json.loads(retry_args_j),
                "succeeded": succeeded,
            })
            self._rows = []
        elif sql_u.startswith("SELECT") and "SELF_CORRECTIONS" in sql_u:
            self._rows = []
        else:
            self._rows = []

    def fetchall(self):
        return list(self._rows)


class TestSelfCorrectorIntegration(unittest.TestCase):
    """
    Mock Claude to emit a RETRY_CALL + SUCCESS.
    Assert exactly 1 self_corrections row with succeeded=True.
    Assert obs event emitted once.
    """

    def setUp(self):
        self.conn = FakeConn()
        self.obs_events: list[tuple[str, dict]] = []

        def fake_obs(event_type, data):
            self.obs_events.append((event_type, data))

        self.obs_fn = fake_obs

    def _mock_claude(self, prompt, model="claude-sonnet-4-6", timeout=300):
        return (0,
                'RETRY_CALL: {"tool": "windows.info", "args": {"case": "smoke-002"}}\n'
                "SUCCESS\n")

    def test_single_retry_succeeds(self):
        sc = SelfCorrector(conn=self.conn, obs_fn=self.obs_fn)

        with unittest.mock.patch("adws.self_correct._run_claude", side_effect=self._mock_claude):
            result = sc.attempt(
                case_id="smoke-002",
                specialist="memory",
                failed_tool="vol3",
                failed_args={"plugin": "windows.malfind"},
                failed_exit=1,
                stderr_tail="Unsatisfied requirement: translation layer",
            )

        self.assertTrue(result, "attempt() must return True when retry succeeds")

        rows = self.conn.rows
        self.assertEqual(len(rows), 1, f"Expected exactly 1 self_corrections row, got {len(rows)}")
        self.assertTrue(rows[0]["succeeded"], "Row must have succeeded=True")

        attempt_events = [e for e in self.obs_events if e[0] == "Sleuth.self_correct.attempt"]
        self.assertEqual(len(attempt_events), 1, "Expected exactly 1 attempt obs event")
        self.assertEqual(attempt_events[0][1]["strategy"], "derive_profile")

        success_events = [e for e in self.obs_events if e[0] == "Sleuth.self_correct.succeeded"]
        self.assertEqual(len(success_events), 1, "Expected exactly 1 succeeded obs event")

    def test_max_retries_not_exceeded(self):
        pre_rows = [
            {"retry_tool": "windows.info", "failed_exit": 1, "succeeded": False},
            {"retry_tool": "windows.info", "failed_exit": 1, "succeeded": False},
            {"retry_tool": "windows.info", "failed_exit": 1, "succeeded": False},
        ]
        for r in pre_rows:
            self.conn.rows.append(r)

        class _FakeConn(FakeConn):
            def cursor(self_inner, cursor_factory=None):
                class _C(FakeCursor):
                    def execute(self_c, sql, params=None):
                        if "SELECT" in sql.upper():
                            self_c._rows = [dict(r) for r in pre_rows]
                        else:
                            super().execute(sql, params)

                return _C(self_inner)

        conn2 = _FakeConn()
        sc = SelfCorrector(conn=conn2, obs_fn=self.obs_fn)

        with unittest.mock.patch("adws.self_correct._run_claude", side_effect=self._mock_claude):
            result = sc.attempt(
                case_id="smoke-003",
                specialist="memory",
                failed_tool="vol3",
                failed_args={},
                failed_exit=1,
                stderr_tail="Unsatisfied requirement",
            )

        self.assertFalse(result, "Must return False when MAX_RETRIES already reached")
        new_rows = [r for r in conn2.rows if "retry_strategy" in r]
        self.assertEqual(len(new_rows), 0, "No new rows should be inserted when at MAX_RETRIES")


if __name__ == "__main__":
    unittest.main(verbosity=2)
