#!/usr/bin/env bash
# Phase 1 smoke test — Gate A.
#
# Asserts:
#   1. Postgres is up with all required tables (es init).
#   2. Broker rejects an unknown tool (allowlist gate works).
#   3. Broker accepts a registered tool with valid args (schema validation works).
#   4. The tool_calls hypertable saw the call.
#   5. evidence-store can record a finding linked to that tool_call.
#   6. `es cite F-001` returns a complete trace.
#   7. The Bash hook denies a non-broker command.
#
# Run from the project root with the dev-server compose stack running:
#     ./tests/phase1_smoke.sh

set -euo pipefail
cd "$(dirname "$0")/.."

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;36m▸\033[0m %s\n' "$*"; }

CASE_ID="smoke-$(date +%s)"

step "1/7  evidence-store init"
./bin/es init
green "ok"

step "2/7  broker rejects unknown tool"
if ./bin/sb exec --case "$CASE_ID" --tool nope --args '{}' 2>/dev/null; then
    red "FAIL — broker accepted unknown tool"; exit 1
fi
green "ok (rejected as expected)"

step "3/7  ensure case row + register a fls tool spec for the test"
psql "postgres://${PG_USER:-sleuth}:${PG_PASSWORD:-changeme-dev-only}@${PG_HOST:-127.0.0.1}:${PG_PORT:-5532}/${PG_DB:-sleuth}" \
  -v ON_ERROR_STOP=1 <<SQL
INSERT INTO cases (case_id, name) VALUES ('$CASE_ID', 'phase 1 smoke')
  ON CONFLICT DO NOTHING;
INSERT INTO tool_specs (tool, image, args_schema)
  VALUES (
    'fls',
    'find-evil-sleuth/sleuthkit:latest',
    '{
      "type":"object",
      "required":["image"],
      "properties":{"image":{"type":"string","pattern":"^/case/"},
                    "offset":{"type":"integer","minimum":0}},
      "additionalProperties":false
    }'::jsonb
  )
  ON CONFLICT (tool) DO UPDATE SET args_schema = EXCLUDED.args_schema;
SQL
green "ok"

step "4/7  broker accepts valid args, records tool_call"
RECEIPT=$(./bin/sb exec --case "$CASE_ID" --tool fls \
                       --args '{"image":"/case/disk.E01","offset":0}')
echo "$RECEIPT" | jq .
TC_ID=$(echo "$RECEIPT" | jq -r .tool_call_id)
[[ -n "$TC_ID" && "$TC_ID" != "null" ]] || { red "FAIL — no tool_call_id"; exit 1; }
green "ok (tool_call_id=$TC_ID)"

step "5/7  evidence-store records finding linked to tool_call"
F_ID=$(./bin/es record-finding \
          --case "$CASE_ID" \
          --specialist disk \
          --claim "Smoke finding linked to broker tool_call" \
          --tool-call-id "$TC_ID" \
          --mitre T1083 \
          --confidence inferred)
[[ "$F_ID" =~ ^F-[0-9]+$ ]] || { red "FAIL — bad finding id $F_ID"; exit 1; }
green "ok (finding=$F_ID)"

step "6/7  es cite returns full trace JSON"
TRACE=$(./bin/es cite "$F_ID")
echo "$TRACE" | jq .
echo "$TRACE" | jq -e '.tool_call.id and .finding_id == "'"$F_ID"'"' >/dev/null \
    || { red "FAIL — cite output missing tool_call linkage"; exit 1; }
green "ok"

step "7/7  hook denies a non-broker bash command"
echo '{"tool_input":{"command":"rm -rf /tmp/anything"}}' \
    | ./.claude/hooks/pre-bash-broker-only.sh && {
        red "FAIL — hook accepted rm -rf"; exit 1; } || green "ok (denied as expected)"

green ""
green "═══════════════════════════════════════════"
green "  Gate A passed.  Phase 1 substrate green."
green "═══════════════════════════════════════════"
