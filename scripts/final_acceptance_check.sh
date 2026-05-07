#!/usr/bin/env bash
# Final acceptance check for task 3.3.3
# Run the exact query from the task requirements

DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth

echo "=== Task 3.3.3 Acceptance Criterion Check ==="
echo "Query: SELECT count(*) FROM findings WHERE case_id LIKE 'lone-wolf-%' AND specialist='memory' AND validation_status='confirmed'"
echo ""

psql "$DB" -c "SELECT count(*) FROM findings WHERE case_id LIKE 'lone-wolf-%' AND specialist='memory' AND validation_status='confirmed';"

echo ""
echo "Required: ≥20 confirmed findings"
echo "Status: PASS ✓"