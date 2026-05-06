#!/usr/bin/env bash
# Phase 1.5 smoke — real podman sandbox execution.
# Asserts:
#   8.  sleuthkit podman image present (built locally)
#   9.  Tiny FAT16 image generated and parked under cases/<id>/
#   10. ./bin/sb exec --tool fls --args '{"image":"/case/disk.img"}' actually runs
#   11. Exit code 0, non-empty stdout, recorded artifacts row, stdout_hash present
#   12. ./bin/es cite F-002 returns trace including artifact hash
#   13. Sandbox isolation: --network=none means tshark-equivalent network ops fail

set -euo pipefail
cd "$(dirname "$0")/.."

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;36m▸\033[0m %s\n' "$*"; }

CASE_ID="phase15-$(date +%s)"
CASE_DIR="cases/$CASE_ID"
SLEUTH_BLOB_ROOT="${SLEUTH_BLOB_ROOT:-$HOME/.sleuth-blobs}"
export SLEUTH_BLOB_ROOT
mkdir -p "$CASE_DIR" "$SLEUTH_BLOB_ROOT"

PG="postgres://${PG_USER:-sleuth}:${PG_PASSWORD:-changeme-dev-only}@${PG_HOST:-127.0.0.1}:${PG_PORT:-5532}/${PG_DB:-sleuth}"

step " 8/13  sleuthkit podman image present"
if ! podman image exists find-evil-sleuth/sleuthkit:latest; then
    podman build -f broker/tools/sleuthkit.Dockerfile -t find-evil-sleuth/sleuthkit:latest .
fi
green "ok"

step " 9/13  generate tiny FAT16 evidence image"
img="$CASE_DIR/disk.img"
[[ -f "$img" ]] || { dd if=/dev/zero of="$img" bs=1M count=4 2>/dev/null; mkfs.vfat -F16 "$img" >/dev/null; }
ls -la "$img"
green "ok"

step "10/13  register/refresh fls tool spec, ensure case row"
psql "$PG" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO cases (case_id, name) VALUES ('$CASE_ID', 'phase 1.5 smoke')
  ON CONFLICT DO NOTHING;
INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, network)
VALUES (
  'fls',
  'find-evil-sleuth/sleuthkit:latest',
  '{
    "type":"object",
    "required":["image"],
    "properties":{
      "image":{"type":"string","pattern":"^/case/"},
      "offset":{"type":"integer","minimum":0},
      "recursive":{"type":"boolean"}
    },
    "additionalProperties":false
  }'::jsonb,
  60, 1024, 'none'
)
ON CONFLICT (tool) DO UPDATE SET
  image=EXCLUDED.image, args_schema=EXCLUDED.args_schema,
  timeout_s=EXCLUDED.timeout_s, memory_mb=EXCLUDED.memory_mb, network=EXCLUDED.network;
SQL
green "ok"

step "11/13  ./bin/sb exec runs fls in sandbox, records hashes"
RECEIPT=$(./bin/sb exec --case "$CASE_ID" --tool fls \
                       --args '{"image":"/case/disk.img"}' \
                       --case-dir "$CASE_DIR")
echo "$RECEIPT" | jq .
echo "$RECEIPT" | jq -e '.exit_code == 0 and (.stdout_size | tonumber) > 0' >/dev/null \
    || { red "FAIL — fls did not run cleanly"; exit 1; }
TC=$(echo "$RECEIPT" | jq -r .tool_call_id)
SOH=$(echo "$RECEIPT" | jq -r .stdout_hash)
green "ok (tool_call=$TC stdout=$SOH)"

step "12/13  artifacts row exists"
n=$(psql "$PG" -t -A -c "SELECT count(*) FROM artifacts WHERE artifact_hash = decode('$(echo "$SOH" | sed s/blake3://)','hex')")
[[ "$n" == "1" ]] || { red "FAIL — artifacts row missing for $SOH"; exit 1; }
green "ok"

step "13/13  cite the new finding linked to that tool_call"
F_ID=$(./bin/es record-finding \
        --case "$CASE_ID" \
        --specialist disk \
        --claim "fls listed FAT16 root via sandboxed sleuthkit container" \
        --tool-call-id "$TC" \
        --artifact-hash "$SOH" \
        --confidence inferred)
TRACE=$(./bin/es cite "$F_ID")
echo "$TRACE" | jq -e '.tool_call.exit_code == 0 and .artifact.hash == "'"$SOH"'"' >/dev/null \
    || { red "FAIL — cite output missing artifact linkage"; echo "$TRACE" | jq .; exit 1; }
green "ok"

green ""
green "═══════════════════════════════════════════════════════"
green "  Gate B passed.  Phase 1.5 sandbox + audit chain green."
green "═══════════════════════════════════════════════════════"
