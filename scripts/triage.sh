#!/usr/bin/env bash
# triage.sh — run the dfir-triage agent against a case directory.
#
# Usage:
#   ./scripts/triage.sh <case_id>
#
# This is the thin shell wrapper the ADW driver calls. It invokes:
#   claude --print --agent triage "Triage case <id> located at cases/<id>/"
#
# The agent reads .claude/agents/find-evil/triage.md (with YAML frontmatter),
# follows .claude/skills/find-evil/dfir-triage/SKILL.md, classifies evidence
# files, inserts case_plan rows into Postgres, and prints the dispatch JSON.
#
# Environment:
#   DATABASE_URL  — override Postgres DSN (default: from .env)
#   MODEL_DEFAULT — Claude model (default: claude-sonnet-4-6)

set -euo pipefail
cd "$(dirname "$0")/.."

CASE_ID="${1:?Usage: $0 <case_id>}"
MODEL="${MODEL_DEFAULT:-claude-sonnet-4-6}"

if [[ ! -d "cases/$CASE_ID" ]]; then
    echo >&2 "Error: cases/$CASE_ID does not exist"
    exit 1
fi

echo >&2 "▸ Triaging case: $CASE_ID"
echo >&2 "▸ Evidence files: $(ls cases/"$CASE_ID"/ | wc -l)"

exec claude --print \
    --model "$MODEL" \
    --agent "find-evil/triage" \
    "Triage case $CASE_ID located at cases/$CASE_ID/. List all evidence files, classify each one, ensure the case exists in Postgres (INSERT INTO cases), insert one case_plan row per specialist found, then print the JSON dispatch."
