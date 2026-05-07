#!/usr/bin/env bash
# Acceptance test for 3.2.6: 10 parallel es record-finding calls must all
# succeed without retry or PK conflict.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ES="${REPO_ROOT}/bin/es"
CASE_ID="seq-race-test-$(date +%s)"
PG_URL="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"

echo "[test_finding_seq] creating test case ${CASE_ID}"
psql "$PG_URL" -c "INSERT INTO cases (case_id, name) VALUES ('${CASE_ID}', 'sequence race test') ON CONFLICT DO NOTHING" >/dev/null

echo "[test_finding_seq] launching 10 parallel record-finding calls for case ${CASE_ID}"

pids=()
outdir=$(mktemp -d)

for i in $(seq 1 10); do
    tc_id="00000000-0000-0000-0000-$(printf '%012d' "$i")"
    "$ES" record-finding \
        --case "$CASE_ID" \
        --specialist "test" \
        --claim "parallel finding $i" \
        --tool-call-id "$tc_id" \
        --confidence high \
        >"${outdir}/out_${i}.txt" 2>&1 &
    pids+=($!)
done

failures=0
for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        failures=$((failures + 1))
    fi
done

echo "[test_finding_seq] results:"
for i in $(seq 1 10); do
    printf "  worker %2d → %s\n" "$i" "$(cat "${outdir}/out_${i}.txt")"
done

rm -rf "$outdir"

if [ "$failures" -gt 0 ]; then
    echo "[test_finding_seq] FAIL: $failures worker(s) failed"
    exit 1
fi

echo "[test_finding_seq] PASS: all 10 parallel workers succeeded without conflict"
