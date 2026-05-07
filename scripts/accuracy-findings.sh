#!/usr/bin/env bash
DSN="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"

echo "=== Confirmed findings from lone-wolf-1778168581 (sample) ==="
psql "$DSN" << 'SQL'
SELECT finding_id, specialist, LEFT(claim, 100) AS claim_preview
FROM findings
WHERE case_id = 'lone-wolf-1778168581'
AND validation_status = 'confirmed'
ORDER BY finding_id
LIMIT 20;
SQL

echo ""
echo "=== All finding IDs for lone-wolf-1778168581 ==="
psql "$DSN" << 'SQL'
SELECT finding_id, specialist, validation_status
FROM findings
WHERE case_id = 'lone-wolf-1778168581'
ORDER BY finding_id;
SQL

echo ""
echo "=== All cases completed ==="
psql "$DSN" << 'SQL'
SELECT case_id, name, status, started_at, finished_at
FROM cases
WHERE status = 'complete'
ORDER BY started_at;
SQL

echo ""
echo "=== Self-corrections count per case ==="
psql "$DSN" << 'SQL'
SELECT
    case_id,
    count(*) AS total_corrections,
    count(*) FILTER (WHERE succeeded = true) AS succeeded,
    count(*) FILTER (WHERE succeeded = false) AS failed
FROM self_corrections
GROUP BY case_id
ORDER BY case_id;
SQL

echo ""
echo "=== Self-corrections: unique correction types ==="
psql "$DSN" << 'SQL'
SELECT
    specialist,
    failed_tool,
    retry_strategy,
    retry_tool,
    count(*) AS occurrences,
    bool_or(succeeded) AS ever_succeeded
FROM self_corrections
GROUP BY specialist, failed_tool, retry_strategy, retry_tool
ORDER BY specialist, failed_tool;
SQL
