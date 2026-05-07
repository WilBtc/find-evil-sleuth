#!/usr/bin/env bash
# tests/test_323_retry_loop.sh
#
# 3.2.3 acceptance: bounded retry loop of MAX_RETRIES=3.
# Runs self_correct_smoke.py unit tests without touching Postgres or Claude.
#
# Done when:
#   - All-fail path: exactly 3 rows in self_corrections, all succeeded=False.
#   - First-succeed path: exactly 1 row, succeeded=True.

set -euo pipefail
cd "$(dirname "$0")/.."

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;36m▸\033[0m %s\n' "$*"; }

step "3.2.3 — Self-correct bounded retry loop (unit)"
./tests/self_correct_smoke.py -v

green "All 3.2.3 tests passed."
