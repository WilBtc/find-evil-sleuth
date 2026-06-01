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


def validate_one(finding_id: str) -> int:
    prompt = (
        f"Validate EXACTLY ONE finding: {finding_id}. Re-execute that finding's original "
        "tool call via ./bin/sb exec, compare against its claim, and set its "
        "validation_status via ./bin/es set-validation (append a validation_history row). "
        "Do NOT touch any other finding. Exit when this one finding is validated."
    )
    rc, _ = run_agent("find-evil/findings-validator", prompt,
                      timeout=TIMEOUT_S, project_root=ROOT)
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
        validate_one(row["finding_id"])

    while not STOP.exists():
        if select.select([conn], [], [], 30) == ([], [], []):
            continue
        conn.poll()
        while conn.notifies:
            note = conn.notifies.pop(0)
            validate_one(note.payload)

    log.info("validate-listener stopping (kill switch present)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
