#!/usr/bin/env bash
# Unit test for pre-bash-broker-only.sh allowlist
# Pipes sample commands as JSON through the hook and asserts exit codes.
# Exit 0 = allowed, exit 2 = blocked (deny).

set -euo pipefail

HOOK="$(dirname "$0")/../.claude/hooks/pre-bash-broker-only.sh"

if [[ ! -x "$HOOK" ]]; then
    echo "FATAL: hook not found or not executable: $HOOK" >&2
    exit 1
fi

pass=0
fail=0

run_hook() {
    local cmd="$1"
    jq -n --arg cmd "$cmd" '{"tool_input":{"command":$cmd}}' | bash "$HOOK" 2>/dev/null
}

assert_allow() {
    local cmd="$1"
    local rc=0
    run_hook "$cmd" || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "PASS (allowed): $cmd"
        ((pass++)) || true
    else
        echo "FAIL (expected allowed, got rc=$rc): $cmd"
        ((fail++)) || true
    fi
}

assert_deny() {
    local cmd="$1"
    local rc=0
    run_hook "$cmd" || rc=$?
    if [[ $rc -eq 2 ]]; then
        echo "PASS (denied):  $cmd"
        ((pass++)) || true
    else
        echo "FAIL (expected rc=2, got rc=$rc): $cmd"
        ((fail++)) || true
    fi
}

echo "=== hook_allowlist.sh unit tests ==="
echo

echo "--- Commands that MUST be DENIED ---"
assert_deny "bash -c 'id'"
assert_deny "sh -c 'whoami'"
assert_deny "cargo build"
assert_deny "ssh somehost ls"
assert_deny "nohup ./bin/sb"
assert_deny "podman run alpine id"
assert_deny "find /case -name '*.img'"
assert_deny "tee /tmp/out.txt"

echo
echo "--- Commands that MUST be ALLOWED ---"
assert_allow "./bin/sb list-tools"
assert_allow "./bin/es record-finding --case x --tool vol3 --stdout y"
assert_allow "jq '.findings' result.json"
assert_allow "grep -r pattern /case"
assert_allow "awk '{print \$1}'"
assert_allow "sed 's/foo/bar/g' file.txt"
assert_allow "head -20 /tmp/output.txt"
assert_allow "tail -50 /tmp/output.txt"
assert_allow "cut -d: -f1 /etc/passwd"
assert_allow "sort -u findings.txt"
assert_allow "wc -l output.txt"
assert_allow "cat result.json"
assert_allow "column -t data.txt"
assert_allow "date"
assert_allow "echo hello"
assert_allow "printf '%s\n' hello"
assert_allow "pwd"
assert_allow "ls /case"
assert_allow "stat /case/disk.img"
assert_allow "file /case/disk.img"
assert_allow "xxd /case/disk.img | head -5"
assert_allow "psql -c 'SELECT 1'"
assert_allow "git status"
assert_allow "git diff HEAD"
assert_allow "git log --oneline -5"
assert_allow "mkdir -p /tmp/out"
assert_allow "touch /tmp/marker"

echo
echo "=== Results: $pass passed, $fail failed ==="

if [[ $fail -gt 0 ]]; then
    exit 1
fi
exit 0
