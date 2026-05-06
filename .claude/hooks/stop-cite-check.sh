#!/usr/bin/env bash
# stop-cite-check.sh — Stop hook for ir-narrator
#
# Fires when the ir-narrator agent session ends. Scans for any report.md
# files written during the session under cases/*/report.md and runs the
# citation checker on each. Exits 0 if all pass; exits 1 to signal the agent
# must re-open and fix any uncited lines.
#
# The Stop hook receives the session transcript as JSON on stdin.

set -u

input_json="$(cat)"

# Only run for the ir-narrator agent (or any agent that writes a report.md).
# Detect by looking for report.md writes in the transcript.
if ! printf '%s' "$input_json" | grep -q 'report\.md'; then
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

all_pass=0
for report in "${report_files[@]}"; do
    if ! bash "${project_dir}/scripts/check-report-citations.sh" "$report"; then
        all_pass=1
    fi
done

exit $all_pass
