#!/usr/bin/env python3
"""
adws/self_correct.py — Phase G structured retry prompt builder.

Given a failed tool call, builds a structured retry prompt, invokes
the broker, persists the outcome in self_corrections, and returns
whether the retry succeeded.

Bounded to MAX_RETRIES attempts per finding_context.

Usage (programmatic, called from investigate.py SELF_CORRECTING state):
    from adws.self_correct import SelfCorrector
    ok = SelfCorrector(conn, obs_fn).attempt(case_id, specialist, failed_call)

Usage (standalone CLI for smoke-testing):
    python adws/self_correct.py --case <id> --specialist memory \
        --tool vol3 --args '{"plugin":"windows.malfind"}' \
        --exit 1 --stderr "Unsatisfied requirement: ..."
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable

log = logging.getLogger("adw.self_correct")

MAX_RETRIES = 3

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth",
)
OBS_URL = os.environ.get("OBS_URL", "http://127.0.0.1:8910")

BIN = Path(__file__).parent.parent / "bin"
SB  = str(BIN / "sb")
ES  = str(BIN / "es")


# ---------------------------------------------------------------------------
# Strategy catalogue
# ---------------------------------------------------------------------------

_STRATEGIES: dict[str, dict] = {
    "derive_profile": {
        "match_stderr": [
            "Unsatisfied requirement",
            "translation layer requirement was not fulfilled",
            "symbol table requirement",
            "no suitable address space",
            "linux.pslist",
            "linux.pstree",
        ],
        "description": (
            "Volatility 3 profile / symbol table mismatch. "
            "Run windows.info or banners to derive the correct OS profile, "
            "then retry the original plugin with the correct profile."
        ),
        "hint_tool": "windows.info",
    },
    "editcap_recover": {
        "match_stderr": [
            "appears to have been cut short",
            "appears to have been cut",
            "truncated",
            "ran past the end of the file",
            "EOF",
        ],
        "description": (
            "PCAP file is truncated. Use editcap to recover the readable portion "
            "of the capture, then retry tshark on the recovered file. "
            "Mark any findings from the recovered file with confidence=partial."
        ),
        "hint_tool": "editcap",
    },
    "adjust_args": {
        "match_stderr": [],
        "description": (
            "Generic argument or invocation error. "
            "Review the stderr output, correct the tool arguments, and retry."
        ),
        "hint_tool": None,
    },
}


def _pick_strategy(failed_tool: str, stderr_tail: str) -> str:
    lower = stderr_tail.lower()
    for name, meta in _STRATEGIES.items():
        for sig in meta["match_stderr"]:
            if sig.lower() in lower:
                return name
    return "adjust_args"


# ---------------------------------------------------------------------------
# Retry-prompt builder
# ---------------------------------------------------------------------------

def build_retry_prompt(
    case_id: str,
    specialist: str,
    failed_tool: str,
    failed_args: dict,
    failed_exit: int,
    stderr_tail: str,
    attempt_number: int,
    prior_attempts: list[dict],
    strategy: str,
) -> str:
    strategy_meta = _STRATEGIES.get(strategy, _STRATEGIES["adjust_args"])
    prior_block = ""
    if prior_attempts:
        lines = []
        for i, a in enumerate(prior_attempts, 1):
            lines.append(
                f"  Attempt {i}: tool={a.get('retry_tool')} "
                f"exit={a.get('failed_exit')} succeeded={a.get('succeeded')}"
            )
        prior_block = "Prior attempts:\n" + "\n".join(lines) + "\n\n"

    return (
        f"SELF-CORRECTION REQUEST (attempt {attempt_number} of {MAX_RETRIES})\n"
        f"Case: {case_id}  Specialist: {specialist}\n\n"
        f"Previous failure:\n"
        f"  Tool:       {failed_tool}\n"
        f"  Args:       {json.dumps(failed_args)}\n"
        f"  Exit code:  {failed_exit}\n"
        f"  Stderr:\n"
        + "\n".join(f"    {line}" for line in stderr_tail.splitlines()[-20:])
        + f"\n\n"
        f"{prior_block}"
        f"Strategy: {strategy}\n"
        f"Strategy description: {strategy_meta['description']}\n"
        + (f"Suggested next tool: {strategy_meta['hint_tool']}\n" if strategy_meta["hint_tool"] else "")
        + "\n"
        "Your task:\n"
        "1. Identify why the tool failed from the stderr above.\n"
        "2. Apply the strategy to determine correct arguments or a preliminary step.\n"
        "3. Emit exactly ONE JSON object on a line starting with RETRY_CALL: like:\n"
        '   RETRY_CALL: {"tool": "<tool_name>", "args": {<corrected args>}}\n'
        "4. Execute the call using ./bin/sb exec --tool <tool> --args '<json>' "
        f"--case {case_id}\n"
        "5. If exit_code is 0, output SUCCESS, else output FAILED.\n"
        "Do NOT output anything except the RETRY_CALL line, the broker invocation, "
        "and the final SUCCESS or FAILED keyword."
    )


# ---------------------------------------------------------------------------
# Broker invocation helper
# ---------------------------------------------------------------------------

def _run_broker(tool: str, args: dict, case_id: str, timeout: int = 120) -> tuple[int, str, str]:
    cmd = [
        SB, "exec",
        "--tool", tool,
        "--args", json.dumps(args),
        "--case", case_id,
    ]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "broker timeout"
    except FileNotFoundError:
        return 127, "", f"binary not found: {SB}"


# ---------------------------------------------------------------------------
# Claude subprocess helper (minimal, no dep on investigate.py)
# ---------------------------------------------------------------------------

def _run_claude(prompt: str, model: str = "claude-sonnet-4-6", timeout: int = 300) -> tuple[int, str]:
    cmd = ["claude", "--print", "--model", model, "--dangerously-skip-permissions", prompt]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout
    except subprocess.TimeoutExpired:
        return 124, ""
    except FileNotFoundError:
        return 127, ""


# ---------------------------------------------------------------------------
# Obs helper (standalone)
# ---------------------------------------------------------------------------

def _obs(event_type: str, data: dict, obs_fn: Callable | None = None):
    if obs_fn:
        obs_fn(event_type, data)
        return
    try:
        payload = json.dumps({"type": event_type, "data": data})
        subprocess.run(
            ["curl", "-m", "2", "-s", "-o", "/dev/null",
             "-X", "POST", "-H", "content-type: application/json",
             "-d", payload, f"{OBS_URL}/event"],
            check=False, capture_output=True,
        )
    except Exception:
        pass


# ---------------------------------------------------------------------------
# DB helpers (standalone — accepts a psycopg2 connection or None)
# ---------------------------------------------------------------------------

def _db_connect():
    import psycopg2
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = True
    return conn


def _db_exec(conn, sql: str, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params)


def _db_query(conn, sql: str, params=None) -> list[dict]:
    import psycopg2.extras
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return cur.fetchall()


# ---------------------------------------------------------------------------
# Core SelfCorrector class
# ---------------------------------------------------------------------------

class SelfCorrector:
    """
    Phase G structured retry engine.

    Typical usage from investigate.py:

        sc = SelfCorrector(conn, obs_fn=obs)
        succeeded = sc.attempt(
            case_id="mini",
            specialist="memory",
            failed_tool="vol3",
            failed_args={"plugin": "windows.malfind"},
            failed_exit=1,
            stderr_tail="Unsatisfied requirement ...",
        )
    """

    def __init__(self, conn=None, obs_fn: Callable | None = None):
        self._conn    = conn
        self._obs_fn  = obs_fn
        self._model   = os.environ.get("MODEL_DEFAULT", "claude-sonnet-4-6")

    def _conn_or_open(self):
        if self._conn is not None:
            return self._conn, False
        return _db_connect(), True

    def attempt(
        self,
        case_id: str,
        specialist: str,
        failed_tool: str,
        failed_args: dict,
        failed_exit: int,
        stderr_tail: str,
    ) -> bool:
        """
        Run up to MAX_RETRIES self-correction cycles.
        Returns True if any attempt succeeded.
        """
        conn, owned = self._conn_or_open()
        try:
            return self._attempt_loop(
                conn, case_id, specialist,
                failed_tool, failed_args, failed_exit, stderr_tail,
            )
        finally:
            if owned:
                conn.close()

    def _attempt_loop(
        self,
        conn,
        case_id: str,
        specialist: str,
        failed_tool: str,
        failed_args: dict,
        failed_exit: int,
        stderr_tail: str,
    ) -> bool:
        prior_rows = _db_query(
            conn,
            "SELECT retry_tool, failed_exit, succeeded "
            "FROM self_corrections "
            "WHERE case_id=%s AND specialist=%s AND failed_tool=%s "
            "ORDER BY created_at",
            (case_id, specialist, failed_tool),
        )

        if len(prior_rows) >= MAX_RETRIES:
            log.warning(
                "Already at MAX_RETRIES=%d for %s/%s/%s — skipping",
                MAX_RETRIES, case_id, specialist, failed_tool,
            )
            return False

        attempt_number = len(prior_rows) + 1
        strategy = _pick_strategy(failed_tool, stderr_tail)

        log.info(
            "self_correct attempt=%d strategy=%s tool=%s case=%s",
            attempt_number, strategy, failed_tool, case_id,
        )
        _obs(
            "Sleuth.self_correct.attempt",
            {
                "case_id": case_id,
                "specialist": specialist,
                "failed_tool": failed_tool,
                "attempt": attempt_number,
                "strategy": strategy,
            },
            self._obs_fn,
        )

        prompt = build_retry_prompt(
            case_id=case_id,
            specialist=specialist,
            failed_tool=failed_tool,
            failed_args=failed_args,
            failed_exit=failed_exit,
            stderr_tail=stderr_tail,
            attempt_number=attempt_number,
            prior_attempts=[dict(r) for r in prior_rows],
            strategy=strategy,
        )

        rc, output = _run_claude(prompt, model=self._model)

        retry_tool, retry_args, succeeded = self._parse_claude_output(
            output, failed_tool, failed_args, case_id,
        )

        _db_exec(
            conn,
            "INSERT INTO self_corrections "
            "(case_id, specialist, failed_tool, failed_args, failed_exit, "
            " stderr_tail, retry_strategy, retry_tool, retry_args, succeeded) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
            (
                case_id, specialist, failed_tool,
                json.dumps(failed_args), failed_exit,
                stderr_tail[:2000],
                strategy, retry_tool,
                json.dumps(retry_args),
                succeeded,
            ),
        )

        if succeeded:
            log.info("self_correct SUCCEEDED (tool=%s)", retry_tool)
            _obs(
                "Sleuth.self_correct.succeeded",
                {"case_id": case_id, "specialist": specialist,
                 "retry_tool": retry_tool, "attempt": attempt_number},
                self._obs_fn,
            )
        else:
            log.warning("self_correct attempt %d FAILED (tool=%s rc=%d)", attempt_number, retry_tool, rc)

        return succeeded

    def _parse_claude_output(
        self,
        output: str,
        failed_tool: str,
        failed_args: dict,
        case_id: str,
    ) -> tuple[str, dict, bool]:
        """
        Parse Claude's structured output:
          RETRY_CALL: {"tool": "...", "args": {...}}
          ...broker invocation emitted by Claude...
          SUCCESS  or  FAILED

        Returns (retry_tool, retry_args, succeeded).
        """
        retry_tool = failed_tool
        retry_args = dict(failed_args)
        succeeded  = False

        for line in output.splitlines():
            stripped = line.strip()
            if stripped.startswith("RETRY_CALL:"):
                payload = stripped[len("RETRY_CALL:"):].strip()
                try:
                    parsed = json.loads(payload)
                    retry_tool = parsed.get("tool", failed_tool)
                    retry_args = parsed.get("args", failed_args)
                except json.JSONDecodeError:
                    log.warning("Could not parse RETRY_CALL JSON: %s", payload)
            elif stripped == "SUCCESS":
                succeeded = True
            elif stripped == "FAILED":
                succeeded = False

        if "SUCCESS" not in output and retry_tool != failed_tool:
            broker_rc, broker_out, broker_err = _run_broker(retry_tool, retry_args, case_id)
            if broker_rc == 0:
                succeeded = True
                log.info("Direct broker retry succeeded: tool=%s", retry_tool)
            else:
                log.warning("Direct broker retry failed: tool=%s exit=%d", retry_tool, broker_rc)

        return retry_tool, retry_args, succeeded


# ---------------------------------------------------------------------------
# Standalone smoke-test / CLI
# ---------------------------------------------------------------------------

def _cli_main():
    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s  %(levelname)-7s  %(message)s",
        datefmt="%H:%M:%S",
    )
    parser = argparse.ArgumentParser(
        description="self_correct.py — standalone smoke-test"
    )
    parser.add_argument("--case",       required=True, help="case_id")
    parser.add_argument("--specialist", required=True, help="specialist name")
    parser.add_argument("--tool",       required=True, help="failed tool name")
    parser.add_argument("--args",       default="{}", help="failed args JSON")
    parser.add_argument("--exit",       type=int, default=1, help="failed exit code")
    parser.add_argument("--stderr",     default="", help="stderr tail from failure")
    parser.add_argument("--dry-run",    action="store_true",
                        help="Build prompt only; do not call Claude or modify DB")
    args = parser.parse_args()

    failed_args_dict = json.loads(args.args)
    strategy = _pick_strategy(args.tool, args.stderr)

    if args.dry_run:
        prompt = build_retry_prompt(
            case_id=args.case,
            specialist=args.specialist,
            failed_tool=args.tool,
            failed_args=failed_args_dict,
            failed_exit=args.exit,
            stderr_tail=args.stderr,
            attempt_number=1,
            prior_attempts=[],
            strategy=strategy,
        )
        print("=== STRATEGY ===")
        print(strategy)
        print()
        print("=== RETRY PROMPT ===")
        print(prompt)
        return 0

    sc = SelfCorrector()
    succeeded = sc.attempt(
        case_id=args.case,
        specialist=args.specialist,
        failed_tool=args.tool,
        failed_args=failed_args_dict,
        failed_exit=args.exit,
        stderr_tail=args.stderr,
    )
    print("RESULT:", "SUCCESS" if succeeded else "FAILED")
    return 0 if succeeded else 1


if __name__ == "__main__":
    sys.exit(_cli_main())
