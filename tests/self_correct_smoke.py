#!/usr/bin/env python3
"""
tests/self_correct_smoke.py

Acceptance tests for self_correct bounded retry loop.

3.2.3: up to MAX_RETRIES=3 retries:
 - All fail  → exactly 3 self_corrections rows (all succeeded=False).
 - First succeeds → exactly 1 self_corrections row (succeeded=True).
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
    """Minimal psycopg2-like connection backed by in-memory lists.

    self_corrections rows are stored in self.sc_rows; SELECT queries
    against self_corrections return the relevant subset so the retry
    loop can track prior attempts.
    """

    def __init__(self):
        self.sc_rows: list[dict] = []

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
            self._conn.sc_rows.append({
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
            if params and len(params) >= 3:
                case_id, specialist, failed_tool = params[0], params[1], params[2]
                self._rows = [
                    {"retry_tool": r["retry_tool"],
                     "failed_exit": r["failed_exit"],
                     "succeeded": r["succeeded"]}
                    for r in self._conn.sc_rows
                    if r["case_id"] == case_id
                    and r["specialist"] == specialist
                    and r["failed_tool"] == failed_tool
                ]
            else:
                self._rows = []
        else:
            self._rows = []

    def fetchall(self):
        return list(self._rows)


class TestSelfCorrectorIntegration(unittest.TestCase):
    """
    3.2.3 acceptance tests: bounded retry loop of MAX_RETRIES=3.

    test_all_fail   — mock Claude always returns FAILED;
                      expect exactly 3 sc rows all succeeded=False, returns False.
    test_first_succeeds — mock Claude succeeds immediately;
                          expect exactly 1 sc row succeeded=True, returns True.
    test_max_retries_not_exceeded — pre-populate 3 rows; no new attempt, returns False.
    """

    def setUp(self):
        self.conn = FakeConn()
        self.obs_events: list[tuple[str, dict]] = []

        def fake_obs(event_type, data):
            self.obs_events.append((event_type, data))

        self.obs_fn = fake_obs

    def _mock_claude_fail(self, prompt, model="claude-sonnet-4-6", timeout=300):
        return (0,
                'RETRY_CALL: {"tool": "vol3", "args": {"plugin": "windows.info"}}\n'
                "FAILED\n")

    def _mock_claude_succeed(self, prompt, model="claude-sonnet-4-6", timeout=300):
        return (0,
                'RETRY_CALL: {"tool": "windows.info", "args": {"case": "smoke-002"}}\n'
                "SUCCESS\n")

    def test_all_fail_exhausts_max_retries(self):
        """3.2.3: all 3 retries fail → 3 rows in self_corrections, returns False."""
        sc = SelfCorrector(conn=self.conn, obs_fn=self.obs_fn)

        with unittest.mock.patch("adws.self_correct._run_claude", side_effect=self._mock_claude_fail):
            result = sc.attempt(
                case_id="smoke-fail",
                specialist="memory",
                failed_tool="vol3",
                failed_args={"plugin": "windows.malfind"},
                failed_exit=1,
                stderr_tail="bad arg: unknown plugin xyz",
            )

        self.assertFalse(result, "attempt() must return False when all retries fail")

        rows = self.conn.sc_rows
        self.assertEqual(len(rows), MAX_RETRIES,
                         f"Expected exactly {MAX_RETRIES} sc rows, got {len(rows)}")
        for row in rows:
            self.assertFalse(row["succeeded"], "All rows must have succeeded=False")

        attempt_events = [e for e in self.obs_events if e[0] == "Sleuth.self_correct.attempt"]
        self.assertEqual(len(attempt_events), MAX_RETRIES,
                         f"Expected {MAX_RETRIES} attempt obs events, got {len(attempt_events)}")

    def test_first_retry_succeeds(self):
        """3.2.3: first retry succeeds → 1 row succeeded=True, returns True."""
        sc = SelfCorrector(conn=self.conn, obs_fn=self.obs_fn)

        with unittest.mock.patch("adws.self_correct._run_claude", side_effect=self._mock_claude_succeed):
            result = sc.attempt(
                case_id="smoke-ok",
                specialist="memory",
                failed_tool="vol3",
                failed_args={"plugin": "windows.malfind"},
                failed_exit=1,
                stderr_tail="Unsatisfied requirement: translation layer",
            )

        self.assertTrue(result, "attempt() must return True when first retry succeeds")

        rows = self.conn.sc_rows
        self.assertEqual(len(rows), 1, f"Expected exactly 1 sc row, got {len(rows)}")
        self.assertTrue(rows[0]["succeeded"], "Row must have succeeded=True")

        attempt_events = [e for e in self.obs_events if e[0] == "Sleuth.self_correct.attempt"]
        self.assertEqual(len(attempt_events), 1, "Expected exactly 1 attempt obs event")
        self.assertEqual(attempt_events[0][1]["strategy"], "derive_profile")

        success_events = [e for e in self.obs_events if e[0] == "Sleuth.self_correct.succeeded"]
        self.assertEqual(len(success_events), 1, "Expected exactly 1 succeeded obs event")

    def test_max_retries_not_exceeded(self):
        """Pre-populate 3 rows; no new attempt, returns False immediately."""
        for i in range(MAX_RETRIES):
            self.conn.sc_rows.append({
                "case_id": "smoke-max",
                "specialist": "memory",
                "failed_tool": "vol3",
                "failed_args": {},
                "failed_exit": 1,
                "stderr_tail": "err",
                "retry_strategy": "adjust_args",
                "retry_tool": "vol3",
                "retry_args": {},
                "succeeded": False,
            })

        sc = SelfCorrector(conn=self.conn, obs_fn=self.obs_fn)

        with unittest.mock.patch("adws.self_correct._run_claude", side_effect=self._mock_claude_succeed):
            result = sc.attempt(
                case_id="smoke-max",
                specialist="memory",
                failed_tool="vol3",
                failed_args={},
                failed_exit=1,
                stderr_tail="Unsatisfied requirement",
            )

        self.assertFalse(result, "Must return False when MAX_RETRIES already reached")
        self.assertEqual(len(self.conn.sc_rows), MAX_RETRIES,
                         "No new rows should be inserted when at MAX_RETRIES")


if __name__ == "__main__":
    unittest.main(verbosity=2)
