#!/usr/bin/env bash
# 2.2.3 Memory-forensics scaffold acceptance test.
#
# Asserts (Done-when criteria):
#   (a) .claude/skills/find-evil/memory-forensics/SKILL.md exists with vol3 playbook
#   (b1) ./bin/sb describe vol3  returns a syntactically valid spec (image + plugin fields)
#   (b2) A synthetic finding is recorded via ./bin/es record-finding whose claim is
#        derived from parsing tests/fixtures/vol3-pslist-sample.txt
#   (c)  BACKLOG line 50 is ticked [x]
#
# Run from project root:
#   ./tests/memory_forensics_scaffold.sh

set -euo pipefail
cd "$(dirname "$0")/.."

SLEUTH_BLOB_ROOT="${SLEUTH_BLOB_ROOT:-$HOME/.sleuth-blobs}"
export SLEUTH_BLOB_ROOT
mkdir -p "$SLEUTH_BLOB_ROOT"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;36m▸\033[0m %s\n' "$*"; }

CASE_ID="mem-scaffold-$(date +%s)"
PG="postgres://${PG_USER:-sleuth}:${PG_PASSWORD:-changeme-dev-only}@${PG_HOST:-127.0.0.1}:${PG_PORT:-5532}/${PG_DB:-sleuth}"
FIXTURE="tests/fixtures/vol3-pslist-sample.txt"

step "1/5  skill file exists with vol3 playbook"
SKILL=".claude/skills/find-evil/memory-forensics/SKILL.md"
[[ -f "$SKILL" ]] || { red "FAIL — $SKILL not found"; exit 1; }
grep -q "windows.pslist\|vol3" "$SKILL" || { red "FAIL — skill has no vol3/pslist playbook"; exit 1; }
green "ok ($SKILL)"

step "2/5  agent file exists"
AGENT=".claude/agents/find-evil/memory-specialist.md"
[[ -f "$AGENT" ]] || { red "FAIL — $AGENT not found"; exit 1; }
grep -q "vol3\|memory" "$AGENT" || { red "FAIL — agent missing vol3 reference"; exit 1; }
green "ok ($AGENT)"

step "3/5  sb describe vol3 returns valid spec (image + plugin fields)"
SPEC=$(./bin/sb describe vol3)
echo "$SPEC" | jq -e '.tool == "vol3" and .args_schema.properties.image and .args_schema.properties.plugin' >/dev/null \
    || { red "FAIL — sb describe vol3 returned unexpected spec"; echo "$SPEC" | jq .; exit 1; }
green "ok (vol3 spec: tool=$(echo "$SPEC" | jq -r .tool) image=$(echo "$SPEC" | jq -r .args_schema.properties.image.type))"

step "4/5  synthetic finding recorded against fixture pslist output"
[[ -f "$FIXTURE" ]] || { red "FAIL — fixture $FIXTURE not found"; exit 1; }

psql "$PG" -v ON_ERROR_STOP=1 -c \
    "INSERT INTO cases (case_id, name) VALUES ('$CASE_ID', 'memory scaffold test') ON CONFLICT DO NOTHING"

TC_ID=$(psql "$PG" -t -A -c \
    "INSERT INTO tool_calls (case_id, tool, args, exit_code, duration_ms, is_validation)
     VALUES ('$CASE_ID', 'vol3',
             '{\"image\":\"/case/$CASE_ID/memory.mem\",\"plugin\":\"windows.pslist\"}'::jsonb,
             0, 0, false)
     RETURNING tool_call_id" | head -1 | tr -d '[:space:]')

[[ -n "$TC_ID" && "$TC_ID" != "null" ]] || { red "FAIL — could not insert stub tool_call row"; exit 1; }
green "  stub tool_call_id=$TC_ID"

PROC_COUNT=$(grep -c "\.exe" "$FIXTURE" || true)
SUSPICIOUS=$(grep -E "a8f3c2d1\.exe|powershell\.exe" "$FIXTURE" | head -2 | \
    awk '{printf "%s(PID=%s) ", $3,$1}' || true)
CLAIM="windows.pslist [fixture]: ${PROC_COUNT} processes; suspicious: ${SUSPICIOUS:-none}"

F_ID=$(./bin/es record-finding \
    --case "$CASE_ID" \
    --specialist memory \
    --claim "$CLAIM" \
    --tool-call-id "$TC_ID" \
    --mitre T1055 \
    --confidence inferred)

[[ "$F_ID" =~ ^F-[0-9]+$ ]] || { red "FAIL — bad finding id '$F_ID'"; exit 1; }
green "ok (finding=$F_ID)"
green "   claim: $CLAIM"

step "5/5  BACKLOG line 2.2.3 ticked [x]"
grep -q '\- \[x\].*2\.2\.3' BACKLOG.md || { red "FAIL — BACKLOG 2.2.3 not ticked"; exit 1; }
green "ok"

green ""
green "═══════════════════════════════════════════════════════════"
green "  2.2.3 scaffold passed — skill + agent + fixture + finding"
green "═══════════════════════════════════════════════════════════"
