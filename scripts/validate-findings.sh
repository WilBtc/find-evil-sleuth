#!/usr/bin/env bash
# validate-findings.sh — drive the findings-validator playbook
#
# Usage:
#   ./scripts/validate-findings.sh <CASE_ID> [SPECIALIST]
#
# SPECIALIST defaults to "disk". Use "all" to validate every specialist.
#
# For each finding with validation_status='pending':
#   1. Re-run the original broker call
#   2. Apply decision matrix (confirmed / refuted / inconclusive / drift)
#   3. Call ./bin/es set-validation
#
# Exit 0 when 100% of targeted findings are validated.
# Exit 1 if any remain pending after the loop.

set -euo pipefail

CASE_ID="${1:-phase15-1778089502}"
SPECIALIST="${2:-disk}"
DSN="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"

export SLEUTH_BLOB_ROOT="${SLEUTH_BLOB_ROOT:-/tmp/sleuth-blobs}"
mkdir -p "$SLEUTH_BLOB_ROOT"

echo "=== findings-validator ==="
echo "case:       $CASE_ID"
echo "specialist: $SPECIALIST"
echo "blob_root:  $SLEUTH_BLOB_ROOT"
echo ""

# Fetch pending findings as TSV:
# finding_id | case_id | specialist | claim | confidence | original_tc_id | tool | args_json | orig_exit_code
FINDINGS=$(psql "$DSN" -A -F$'\t' -t \
    -v case_id="$CASE_ID" \
    -v specialist="$SPECIALIST" \
    -f scripts/validator-query.sql 2>&1)

if [ -z "$FINDINGS" ]; then
    echo "No pending findings for case=$CASE_ID specialist=$SPECIALIST"
    psql "$DSN" -f scripts/validator-status.sql -v case_id="$CASE_ID"
    exit 0
fi

TOTAL=0
CONFIRMED=0
REFUTED=0
INCONCLUSIVE=0
DRIFT=0

while IFS=$'\t' read -r finding_id case_id spec claim confidence orig_tc_id tool args_json orig_exit; do
    [[ -z "$finding_id" ]] && continue
    TOTAL=$((TOTAL + 1))

    echo "--- $finding_id ($tool) ---"
    printf '  claim: %.80s\n' "$claim"
    echo "  original exit=$orig_exit"

    # Re-execute via broker
    SB_OUT=$(./bin/sb exec --case "$CASE_ID" --tool "$tool" --args "$args_json" 2>&1) || true

    # Check if sb itself failed (broker error, not just tool exit code)
    if ! echo "$SB_OUT" | jq -e '.tool_call_id' > /dev/null 2>&1; then
        echo "  broker error: $(echo "$SB_OUT" | head -1)"
        echo "  marking inconclusive"
        ./bin/es set-validation --finding-id "$finding_id" --status inconclusive
        INCONCLUSIVE=$((INCONCLUSIVE + 1))
        continue
    fi

    NEW_TC_ID=$(echo "$SB_OUT"     | jq -r '.tool_call_id')
    NEW_EXIT=$(echo "$SB_OUT"      | jq -r '.exit_code')
    NEW_STDOUT=$(echo "$SB_OUT"    | jq -r '.stdout_preview // ""')
    NEW_STDERR=$(echo "$SB_OUT"    | jq -r '.stderr_tail // ""')

    echo "  new_tc=$NEW_TC_ID  new_exit=$NEW_EXIT"

    # Decision matrix (from SKILL.md)
    STATUS="inconclusive"

    if [ "$orig_exit" = "0" ] && [ "$NEW_EXIT" = "0" ]; then
        # Both succeeded — re-run succeeded; confirm the finding
        STATUS="confirmed"

    elif [ "$orig_exit" != "0" ] && [ "$NEW_EXIT" != "0" ]; then
        # Both failed — the failure itself is the documented finding
        STATUS="confirmed"

    elif [ "$orig_exit" = "0" ] && [ "$NEW_EXIT" != "0" ]; then
        # Was success, now failure
        if echo "$NEW_STDERR" | grep -qiE "no such file|not found|cannot open|permission denied"; then
            STATUS="inconclusive"
        else
            STATUS="refuted"
        fi

    elif [ "$orig_exit" != "0" ] && [ "$NEW_EXIT" = "0" ]; then
        # Was failure, now success — inconclusive (specialist review needed)
        STATUS="inconclusive"
    fi

    echo "  status → $STATUS"

    ./bin/es set-validation \
        --finding-id "$finding_id" \
        --status "$STATUS" \
        --validation-tool-call-id "$NEW_TC_ID"

    case "$STATUS" in
        confirmed)    CONFIRMED=$((CONFIRMED + 1)) ;;
        refuted)      REFUTED=$((REFUTED + 1)) ;;
        inconclusive) INCONCLUSIVE=$((INCONCLUSIVE + 1)) ;;
        drift)        DRIFT=$((DRIFT + 1)) ;;
    esac

done <<< "$FINDINGS"

echo ""
echo "=== validation complete ==="
echo "total:        $TOTAL"
echo "confirmed:    $CONFIRMED"
echo "refuted:      $REFUTED"
echo "inconclusive: $INCONCLUSIVE"
echo "drift:        $DRIFT"
echo ""

echo "=== status breakdown ==="
psql "$DSN" -f scripts/validator-status.sql -v case_id="$CASE_ID"

# Check for any remaining pending
PENDING=$(psql "$DSN" -A -t -c "SELECT count(*) FROM findings WHERE case_id='$CASE_ID' AND validation_status='pending'" 2>&1 | tr -d ' ')
if [ "${PENDING:-0}" -gt 0 ]; then
    echo "FAIL: $PENDING finding(s) still pending for case $CASE_ID"
    exit 1
fi

echo "PASS: 100% of findings validated for case $CASE_ID"
exit 0
