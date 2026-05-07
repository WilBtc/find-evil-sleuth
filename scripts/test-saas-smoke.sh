#!/usr/bin/env bash
# Smoke test: start sleuth-saas, curl /, assert HTML returned, stop.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${REPO_ROOT}/bin/sleuth-saas"
PORT=8932

if [ ! -x "${BIN}" ]; then
    echo "FAIL: ${BIN} not found or not executable" >&2
    exit 1
fi

echo "[smoke] Starting sleuth-saas on port ${PORT}..."
"${BIN}" &
SAAS_PID=$!
trap "kill ${SAAS_PID} 2>/dev/null || true" EXIT

sleep 2

echo "[smoke] Curling http://127.0.0.1:${PORT}/ ..."
RESPONSE="$(curl -sf http://127.0.0.1:${PORT}/)"
echo "${RESPONSE}" | head -5

if echo "${RESPONSE}" | grep -q "find-evil-sleuth"; then
    echo "[smoke] PASS: layout HTML returned (contains 'find-evil-sleuth')"
else
    echo "[smoke] FAIL: response does not contain expected content" >&2
    exit 1
fi
