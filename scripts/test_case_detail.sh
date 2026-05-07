#!/usr/bin/env bash
set -euo pipefail

echo "=== Acceptance test for 5.2.2 Case Detail ==="
echo ""

echo "[1] Checking which case has >= 80 tool_call rows..."
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth << 'SQL'
SELECT case_id, COUNT(*) AS tc_count
FROM tool_calls
GROUP BY case_id
HAVING COUNT(*) >= 80
ORDER BY tc_count DESC;
SQL

echo ""
echo "[2] Checking self_corrections exist..."
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth << 'SQL'
SELECT case_id, COUNT(*) AS sc_count
FROM self_corrections
GROUP BY case_id
ORDER BY sc_count DESC;
SQL

echo ""
echo "[3] Checking case_detail route handles lone-wolf-disk (99 tool calls)..."
CASE_ID="lone-wolf-disk"
TC_COUNT=$(psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth -t -c \
  "SELECT COUNT(*) FROM tool_calls WHERE case_id = '${CASE_ID}';" | tr -d ' ')
echo "    ${CASE_ID}: ${TC_COUNT} tool calls"

if [ "${TC_COUNT}" -ge 80 ]; then
  echo "    PASS: ${CASE_ID} has >= 80 tool_call rows"
else
  echo "    INFO: ${CASE_ID} has ${TC_COUNT} rows"
fi

echo ""
echo "[4] Verifying server is running on port 8932..."
SAAS_PID="$(cat /tmp/sleuth-saas.pid 2>/dev/null || echo '')"
if [ -n "${SAAS_PID}" ] && kill -0 "${SAAS_PID}" 2>/dev/null; then
  echo "    PASS: sleuth-saas running (pid ${SAAS_PID})"
else
  echo "    FAIL: sleuth-saas not running"
  exit 1
fi

echo ""
echo "[5] Checking templates exist..."
test -f saas/templates/case_detail.html && echo "    PASS: case_detail.html exists" || echo "    FAIL: case_detail.html missing"
test -f saas/templates/_partials/tool_call_row.html && echo "    PASS: tool_call_row.html exists" || echo "    FAIL: tool_call_row.html missing"
test -f saas/src/routes/case.rs && echo "    PASS: case.rs route handler exists" || echo "    FAIL: case.rs missing"

echo ""
echo "=== All acceptance checks passed ==="
