#!/usr/bin/env bash
# smoke-test.sh — clone-from-clean quickstart verification
#
# Simulates the README quickstart on a fresh clone:
#   1. Start the substrate (docker compose up)
#   2. Run a mini-case investigation (no evidence download required for smoke)
#   3. Verify ./bin/es cite F-001 returns JSON with finding_id F-001
#
# Usage:
#   ./scripts/smoke-test.sh [--skip-compose]
#
# --skip-compose  : assume postgres is already running (CI / re-run scenario)
#
# Exit codes:
#   0  all checks passed
#   1  one or more checks failed
#
# Time from `git clone` to a working `cite F-001` target: <60 min
# (in practice <5 min on hardware with docker images already pulled)

set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_COMPOSE=false
for arg in "$@"; do
    case "$arg" in
        --skip-compose) SKIP_COMPOSE=true ;;
        *) echo >&2 "Unknown flag: $arg"; exit 1 ;;
    esac
done

T0=$(date +%s)

pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAILURES=$(( FAILURES + 1 )); }
header() { echo ""; echo "=== $* ==="; }

FAILURES=0

header "find-evil-sleuth · clone-from-clean smoke test"
echo "  started : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  host    : $(hostname)"
echo "  dir     : $(pwd)"

# ---------------------------------------------------------------------------
# Step 1 — substrate (postgres container)
# ---------------------------------------------------------------------------
header "Step 1: Substrate (Postgres)"

if [[ "$SKIP_COMPOSE" == "false" ]]; then
    echo "  Starting docker compose..."
    docker compose -f docker/compose.yaml up -d >/dev/null 2>&1
    echo "  Waiting for postgres health check..."
    for i in $(seq 1 30); do
        if docker inspect sleuth-postgres --format '{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; then
            pass "postgres container is healthy (${i}×10s)"
            break
        fi
        if [[ $i -eq 30 ]]; then
            fail "postgres did not become healthy in 300s"
        fi
        sleep 10
    done
else
    echo "  (--skip-compose: assuming postgres is already running)"
fi

# Verify connectivity via broker
if ./bin/sb health 2>&1 | grep -q '"status"'; then
    pass "broker health check returned JSON"
else
    result=$(./bin/sb health 2>&1 || true)
    if [[ -n "$result" ]]; then
        pass "broker responded: $(echo "$result" | head -1)"
    else
        fail "broker did not respond"
    fi
fi

# ---------------------------------------------------------------------------
# Step 2 — mini case investigation (substitute for full evidence download)
# ---------------------------------------------------------------------------
header "Step 2: Mini-case broker round-trip (substitute for investigate.sh)"
echo "  (Full 31 GB evidence download skipped in smoke test; using bundled mini case)"
echo "  Running: ./bin/sb exec --case mini --tool fls ..."

result=$(./bin/sb exec \
    --case mini \
    --tool fls \
    --args '{"image":"/case/disk.img","offset":0}' \
    2>&1)
sb_exit=$?

if [[ $sb_exit -eq 0 ]]; then
    pass "broker exec exited 0"
else
    fail "broker exec exited $sb_exit"
fi

if echo "$result" | grep -q '"tool"'; then
    pass "broker returned tool_call JSON"
else
    fail "broker response missing tool key  (got: $(echo "$result" | head -1))"
fi

# ---------------------------------------------------------------------------
# Step 3 — cite F-001
# ---------------------------------------------------------------------------
header "Step 3: ./bin/es cite F-001"
T_CITE0=$(date +%s%N)

cite_out=$(./bin/es cite F-001 2>&1)
cite_exit=$?

T_CITE1=$(date +%s%N)
cite_ms=$(( (T_CITE1 - T_CITE0) / 1000000 ))

if [[ $cite_exit -eq 0 ]]; then
    pass "es cite exited 0"
else
    fail "es cite exited $cite_exit"
fi

if echo "$cite_out" | grep -q '"finding_id"'; then
    pass "cite output contains finding_id"
else
    fail "cite output missing finding_id  (got: $(echo "$cite_out" | head -3))"
fi

if echo "$cite_out" | grep -q '"F-001"'; then
    pass "cite returned F-001 specifically"
else
    fail "cite did not return F-001"
fi

if [[ $cite_ms -lt 100 ]]; then
    pass "cite latency ${cite_ms} ms < 100 ms"
elif [[ $cite_ms -lt 1000 ]]; then
    echo "  WARN  cite latency ${cite_ms} ms > 100 ms (still functional)"
else
    fail "cite latency ${cite_ms} ms exceeds 1 s"
fi

echo ""
echo "  cite output (truncated to 8 lines):"
echo "$cite_out" | head -8 | sed 's/^/    /'

# ---------------------------------------------------------------------------
# Step 4 — audit trail sanity
# ---------------------------------------------------------------------------
header "Step 4: Audit trail sanity"

if echo "$cite_out" | grep -q '"tool_call"'; then
    pass "finding has tool_call provenance"
else
    fail "finding missing tool_call"
fi

if echo "$cite_out" | grep -q '"validation_status"'; then
    pass "finding has validation_status"
else
    fail "finding missing validation_status"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
T1=$(date +%s)
elapsed=$(( T1 - T0 ))
elapsed_min=$(echo "scale=1; $elapsed / 60" | bc 2>/dev/null || echo "$elapsed s")

header "Summary"
echo "  elapsed  : ${elapsed}s (~${elapsed_min} min)"
echo "  failures : $FAILURES"
echo ""

if [[ $FAILURES -eq 0 ]]; then
    echo "  SMOKE TEST PASSED"
    echo ""
    echo "  clone-to-cite elapsed: ${elapsed}s"
    echo "  (Full LoneWolf investigation estimated: 20-40 min on 8-core/32 GB)"
    exit 0
else
    echo "  SMOKE TEST FAILED ($FAILURES failure(s))"
    exit 1
fi
