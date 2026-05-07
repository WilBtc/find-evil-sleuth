#!/usr/bin/env bash
# export-execution-log.sh
# Dumps the full audit trail from the sleuth DB to submission/execution-log.ndjson.
# Each line is a valid JSON object tagged with "event_type" and "ts" (timestamp).
# Tables exported (sorted by timestamp across all):
#   tool_calls, findings, validation_history, validation_runs, self_corrections
#
# Usage:
#   ./scripts/export-execution-log.sh [case_id]
#
# If case_id is supplied only records for that case are exported.
# With no argument all cases are exported.

set -euo pipefail

DSN="${SLEUTH_DSN:-postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth}"
OUT_DIR="submission"
OUT_FILE="${OUT_DIR}/execution-log.ndjson"

mkdir -p "${OUT_DIR}"

CASE_FILTER="${1:-}"

# Build optional WHERE fragment; injected via psql -v
# psql -v case_filter='' → all rows; otherwise filter by case_id
if [[ -n "${CASE_FILTER}" ]]; then
    CASE_SQL="AND case_id = '${CASE_FILTER}'"
else
    CASE_SQL=""
fi

: > "${OUT_FILE}"

# ── 1. tool_calls ──────────────────────────────────────────────────────────────
psql "${DSN}" -qAX -F '' -c "
SELECT row_to_json(r)
FROM (
    SELECT
        'tool_call'                       AS event_type,
        started_at                        AS ts,
        tool_call_id::text                AS tool_call_id,
        case_id,
        tool,
        args,
        exit_code,
        duration_ms,
        container_id,
        is_validation,
        finished_at
    FROM tool_calls
    WHERE true
    ORDER BY started_at
) r;
" >> "${OUT_FILE}"

# ── 2. findings ────────────────────────────────────────────────────────────────
psql "${DSN}" -qAX -F '' -c "
SELECT row_to_json(r)
FROM (
    SELECT
        'finding'                         AS event_type,
        created_at                        AS ts,
        finding_id,
        case_id,
        specialist,
        claim,
        confidence,
        validation_status,
        mitre_technique,
        tool_call_id::text                AS tool_call_id,
        superseded_by,
        last_validated_at
    FROM findings
    ORDER BY created_at
) r;
" >> "${OUT_FILE}"

# ── 3. validation_history ──────────────────────────────────────────────────────
psql "${DSN}" -qAX -F '' -c "
SELECT row_to_json(r)
FROM (
    SELECT
        'validation_history'              AS event_type,
        validated_at                      AS ts,
        history_id,
        finding_id,
        status,
        validation_tool_call_id::text     AS validation_tool_call_id
    FROM validation_history
    ORDER BY validated_at
) r;
" >> "${OUT_FILE}"

# ── 4. validation_runs ─────────────────────────────────────────────────────────
psql "${DSN}" -qAX -F '' -c "
SELECT row_to_json(r)
FROM (
    SELECT
        'validation_run'                  AS event_type,
        started_at                        AS ts,
        run_id::text                      AS run_id,
        finding_id,
        result,
        diff
    FROM validation_runs
    ORDER BY started_at
) r;
" >> "${OUT_FILE}"

# ── 5. self_corrections ────────────────────────────────────────────────────────
psql "${DSN}" -qAX -F '' -c "
SELECT row_to_json(r)
FROM (
    SELECT
        'self_correction'                 AS event_type,
        created_at                        AS ts,
        attempt_id::text                  AS attempt_id,
        case_id,
        specialist,
        failed_tool,
        failed_args,
        failed_exit,
        stderr_tail,
        retry_strategy,
        retry_tool,
        retry_args,
        succeeded
    FROM self_corrections
    ORDER BY created_at
) r;
" >> "${OUT_FILE}"

# ── Sort entire file by ts field ───────────────────────────────────────────────
# Use a Python one-liner (safe: only reads/writes local file, no network).
python3 - "${OUT_FILE}" << 'PYEOF'
import sys, json
path = sys.argv[1]
rows = []
with open(path) as fh:
    for line in fh:
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            pass
rows.sort(key=lambda r: r.get("ts", ""))
with open(path, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r, default=str) + "\n")
PYEOF

LINE_COUNT=$(wc -l < "${OUT_FILE}")
echo "Exported ${LINE_COUNT} events to ${OUT_FILE}"

if [[ "${LINE_COUNT}" -lt 500 ]]; then
    echo "WARNING: only ${LINE_COUNT} lines — acceptance criterion requires >500." >&2
    exit 1
fi
echo "OK: ${LINE_COUNT} > 500"
