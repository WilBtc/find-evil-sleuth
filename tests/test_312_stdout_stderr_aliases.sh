#!/usr/bin/env bash
# Acceptance test for task 3.1.2:
# Verify broker JSON output contains .stdout, .stderr, .stdout_preview, .stderr_tail
#
# Done when:
#   ./bin/sb exec ... | jq -e '.stdout and .stderr and .stdout_preview and .stderr_tail'
#   returns true (exit 0)

set -euo pipefail
cd "$(dirname "$0")/.."

SLEUTH_BLOB_ROOT="${SLEUTH_BLOB_ROOT:-$(pwd)/var/sleuth/blobs}"
export SLEUTH_BLOB_ROOT
mkdir -p "$SLEUTH_BLOB_ROOT"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

echo "SLEUTH_BLOB_ROOT=$SLEUTH_BLOB_ROOT"

CASE="mini"
TOOL="fls"
ARGS='{"image":"/case/disk.img","recursive":true}'

echo "Running: ./bin/sb exec --case $CASE --tool $TOOL --args '$ARGS'"
OUTPUT=$(./bin/sb exec --case "$CASE" --tool "$TOOL" --args "$ARGS" 2>&1)

echo "--- broker output ---"
echo "$OUTPUT"
echo "---"

echo "$OUTPUT" | jq -e '.stdout and .stderr and .stdout_preview and .stderr_tail' \
    && green "PASS: all four keys present (.stdout, .stderr, .stdout_preview, .stderr_tail)" \
    || { red "FAIL: one or more keys missing"; exit 1; }
