#!/usr/bin/env bash
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
echo "=== Cases ==="
psql "$DB" -c "SELECT case_id, name, status FROM cases ORDER BY case_id;"
echo ""
echo "=== Findings by case and specialist ==="
psql "$DB" -c "SELECT case_id, specialist, validation_status, count(*) FROM findings GROUP BY case_id, specialist, validation_status ORDER BY case_id, specialist;"
