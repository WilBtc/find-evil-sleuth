#!/usr/bin/env bash
# check-report-citations.sh — citation hook for ir-narrator
#
# Verifies that every factual claim line in report.md is backed by at least
# one [F-NNN] citation. Exits 0 if the report passes; exits 1 with a list of
# uncited lines if it fails.
#
# Usage:  bash scripts/check-report-citations.sh <report_file>
#         bash scripts/check-report-citations.sh cases/phase15-1778089502/report.md
#
# A "claim line" is any non-blank line that:
#   - Contains at least one word character (alphabetic content)
#   - Is NOT a Markdown heading  (starts with #)
#   - Is NOT a horizontal rule   (--- alone or === alone)
#   - Is NOT a table row         (starts with |)
#   - Is NOT inside a code fence (between ``` markers)
#   - Is NOT a metadata key-value line (starts with ** or starts with > )
#   - Is NOT the report front-matter block (lines before the first ---)
#
# For each claim line, the checker requires [F- to appear on the line.

set -euo pipefail

REPORT="${1:-}"
if [[ -z "$REPORT" ]]; then
    echo "Usage: $0 <report_file>" >&2
    exit 1
fi

if [[ ! -f "$REPORT" ]]; then
    echo "Error: report file not found: $REPORT" >&2
    exit 1
fi

errors=0
in_code_block=0
line_num=0
declare -a bad_lines=()

while IFS= read -r line; do
    line_num=$(( line_num + 1 ))

    # Track code fences (``` or ~~~)
    if [[ "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
        if [[ $in_code_block -eq 0 ]]; then
            in_code_block=1
        else
            in_code_block=0
        fi
        continue
    fi
    [[ $in_code_block -eq 1 ]] && continue

    # Skip blank lines
    [[ -z "${line// /}" ]] && continue

    # Skip Markdown headings
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Skip horizontal rules (--- or === or *** alone on line)
    [[ "$line" =~ ^[[:space:]]*(-{3,}|={3,}|\*{3,})[[:space:]]*$ ]] && continue

    # Skip table rows
    [[ "$line" =~ ^[[:space:]]*\| ]] && continue

    # Skip metadata / front-matter lines (bold key-value: **Key:** value)
    [[ "$line" =~ ^\*\* ]] && continue

    # Skip blockquote lines
    [[ "$line" =~ ^[[:space:]]*\> ]] && continue

    # Skip lines that are only punctuation / formatting with no words
    if ! [[ "$line" =~ [a-zA-Z] ]]; then
        continue
    fi

    # This is a claim line — it must have a [F- citation
    if ! [[ "$line" =~ \[F- ]]; then
        bad_lines+=("  line ${line_num}: ${line}")
        errors=$(( errors + 1 ))
    fi

done < "$REPORT"

if [[ $errors -gt 0 ]]; then
    echo "CITATION CHECK FAILED: ${errors} uncited claim line(s) in ${REPORT}" >&2
    for bl in "${bad_lines[@]}"; do
        echo "$bl" >&2
    done
    exit 1
fi

echo "Citation check PASSED: all claim lines in ${REPORT} have [F-NNN] citations."
exit 0
