#!/usr/bin/env python3
"""
adws/validate_listener.py — per-finding validation worker (replaces the time-based
pg_cron sweep). LISTENs on the 'finding_validate' NOTIFY channel; for each finding_id
it validates exactly that ONE finding by invoking the findings-validator agent, which
re-executes the finding's tool call and sets its validation_status. Event-driven, no
clock, no human input.

Run:   python3 -m adws.validate_listener           (from project root)
Stop:  touch ~/.validate-listener-stop             (graceful, at next wakeup)
Env:   VALIDATE_FINDING_TIMEOUT_S=600  DATABASE_URL=...
"""
from __future__ import annotations
import os, select, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import psycopg2.extensions
from adws.investigate import db_connect, db_query, run_agent, log

STOP = Path.home() / ".validate-listener-stop"
TIMEOUT_S = int(os.environ.get("VALIDATE_FINDING_TIMEOUT_S", "600"))


MAX_FAILS = int(os.environ.get("VALIDATE_MAX_FAILS", "3"))  # per-finding ceiling → no runaway
_fail_counts: dict[str, int] = {}


def validate_one(conn, finding_id: str) -> int:
    # Idempotent: re-query current status; skip if already validated (e.g. by the
    # investigation's batch validator) — prevents double-validation cost.
    rows = db_query(conn, "SELECT validation_status FROM findings WHERE finding_id = %s",
                    (finding_id,))
    if not rows:
        return 0
    if rows[0]["validation_status"] != "pending":
        log.info("skip %s (already %s)", finding_id, rows[0]["validation_status"])
        return 0
    # Attempt ceiling: stop re-spawning agents on a finding that keeps failing.
    if _fail_counts.get(finding_id, 0) >= MAX_FAILS:
        log.warning("skip %s (hit %d-fail ceiling)", finding_id, MAX_FAILS)
        return 1
    prompt = (
        f"Validate EXACTLY ONE finding: {finding_id}. Re-execute that finding's original "
        "tool call via ./bin/sb exec, compare against its claim, and set its "
        "validation_status via ./bin/es set-validation (append a validation_history row). "
        "Do NOT touch any other finding. Exit when this one finding is validated."
    )
    rc, _ = run_agent("find-evil/findings-validator", prompt,
                      timeout=TIMEOUT_S, project_root=ROOT)
    if rc != 0:
        _fail_counts[finding_id] = _fail_counts.get(finding_id, 0) + 1
    log.info("validated %s (rc=%d)", finding_id, rc)
    return rc


def main() -> int:
    conn = db_connect()
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    with conn.cursor() as cur:
        cur.execute("LISTEN finding_validate;")
    log.info("validate-listener up — LISTEN finding_validate (per-finding, no clock)")

    # Catch-up: validate anything already pending (e.g. created while we were down).
    for row in db_query(conn, "SELECT finding_id FROM findings WHERE validation_status = 'pending'"):
        if STOP.exists():
            break
        validate_one(conn, row["finding_id"])

    while not STOP.exists():
        if select.select([conn], [], [], 30) == ([], [], []):
            continue
        conn.poll()
        # Dedup the burst: many NOTIFYs for the same finding collapse to one validation.
        batch: list[str] = []
        while conn.notifies:
            fid = conn.notifies.pop(0).payload
            if fid not in batch:
                batch.append(fid)
        for fid in batch:
            if STOP.exists():
                break
            validate_one(conn, fid)

    log.info("validate-listener stopping (kill switch present)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
