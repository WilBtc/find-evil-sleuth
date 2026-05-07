#!/usr/bin/env bash
# stop-cite-check.sh — Stop hook for ir-narrator
#
# Fires when the ir-narrator agent session ends. Scans for any report.md
# files written during the session under cases/*/report.md and runs the
# citation checker on each. Exits 0 if all pass; exits 2 (blocking) to
# signal the agent must re-open and fix any uncited lines.
#
# The Stop hook receives the session transcript as JSON on stdin.
# Per the Stop hook contract, exit 2 blocks the agent from stopping.

set -u

input_json="$(cat)"

# Gate on agent identity: only run for the ir-narrator subagent.
# Read .subagent_type from the input JSON (not a transcript grep).
subagent_type="$(printf '%s' "$input_json" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('subagent_type',''))" \
    2>/dev/null || true)"

if [[ "$subagent_type" != "ir-narrator" ]]; then
    exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-.}"

# Find all report.md files in the cases directory
report_files=()
while IFS= read -r -d '' f; do
    report_files+=("$f")
done < <(find "${project_dir}/cases" -name 'report.md' -print0 2>/dev/null)

if [[ ${#report_files[@]} -eq 0 ]]; then
    exit 0
fi

failed_reports=()
for report in "${report_files[@]}"; do
    if ! bash "${project_dir}/scripts/check-report-citations.sh" "$report"; then
        failed_reports+=("$report")
    fi
done

if [[ ${#failed_reports[@]} -gt 0 ]]; then
    printf 'Citation check failed for: %s\n' "${failed_reports[@]}" >&2
    exit 2
fi

exit 0
