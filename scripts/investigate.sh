#!/usr/bin/env bash
# investigate.sh — user-facing entrypoint for the find-evil-sleuth ADW driver.
#
# Usage:
#   ./scripts/investigate.sh <case-dir> [--no-self-correct]
#
# Examples:
#   ./scripts/investigate.sh ./cases/mini/
#   ./scripts/investigate.sh ./cases/phase15-1778089502/ --no-self-correct
#
# The driver (adws/investigate.py) runs the full pipeline:
#   INIT → TRIAGE → DISPATCH → SPECIALISTS_RUNNING → VALIDATING → NARRATING → DONE
#
# On completion a report.md is written inside <case-dir>/.
#
# Environment overrides:
#   DATABASE_URL  — Postgres DSN (default: postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth)
#   MODEL_DEFAULT — Claude model for specialists  (default: claude-sonnet-4-6)
#   MODEL_NARRATOR — Claude model for narrator    (default: claude-sonnet-4-6)
#   OBS_URL       — agent-obs endpoint            (default: http://127.0.0.1:8910)

set -euo pipefail
cd "$(dirname "$0")/.."

CASE_DIR="${1:?Usage: $0 <case-dir> [--no-self-correct]}"
shift
EXTRA_ARGS=("$@")

if [[ ! -d "$CASE_DIR" ]]; then
    echo >&2 "Error: case directory does not exist: $CASE_DIR"
    exit 1
fi

CASE_ID="$(basename "$CASE_DIR")"
echo >&2 ""
echo >&2 "╔══════════════════════════════════════════════════════════╗"
echo >&2 "║  find-evil-sleuth  ·  ADW investigation driver           ║"
echo >&2 "╚══════════════════════════════════════════════════════════╝"
echo >&2 ""
echo >&2 "  case dir : $CASE_DIR"
echo >&2 "  case id  : $CASE_ID"
echo >&2 "  model    : ${MODEL_DEFAULT:-claude-sonnet-4-6}"
echo >&2 ""

exec python3 adws/investigate.py "$CASE_DIR" "${EXTRA_ARGS[@]}"
