#!/usr/bin/env bash
# Run the full investigate.sh end-to-end for task 3.3.5
# Captures output to a log file for the acceptance proof
cd "$(dirname "$0")/.."

LOG_FILE="cases/lone-wolf-1778168581/investigate_335.log"
mkdir -p cases/lone-wolf-1778168581

./scripts/investigate.sh cases/lone-wolf-1778168581/ 2>&1 > "$LOG_FILE"
RC=$?

echo "Investigation exit code: $RC"
echo "Log: $LOG_FILE"

if [ -f "cases/lone-wolf-1778168581/report.md" ]; then
    echo "SUCCESS: report.md exists"
    wc -l "cases/lone-wolf-1778168581/report.md"
else
    echo "FAIL: report.md not found"
fi

exit $RC
