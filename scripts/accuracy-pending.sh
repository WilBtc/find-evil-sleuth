#!/usr/bin/env bash
DSN="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"

echo "=== Pending findings details (known misses) ==="
psql "$DSN" << 'SQL'
SELECT
    f.finding_id,
    f.case_id,
    f.specialist,
    f.confidence,
    LEFT(f.claim, 120) AS claim_preview
FROM findings f
WHERE f.validation_status = 'pending'
AND f.case_id NOT LIKE 'test%'
AND f.case_id NOT LIKE 'seq%'
AND f.case_id NOT LIKE 'smoke%'
AND f.case_id NOT LIKE 'phase%'
AND f.case_id NOT LIKE 'mem-scaffold%'
ORDER BY f.case_id, f.specialist, f.finding_id
LIMIT 30;
SQL

echo ""
echo "=== Mini case findings breakdown ==="
psql "$DSN" << 'SQL'
SELECT
    validation_status,
    specialist,
    count(*) AS count
FROM findings
WHERE case_id = 'mini'
GROUP BY validation_status, specialist
ORDER BY validation_status, specialist;
SQL

echo ""
echo "=== Net-scaffold findings breakdown ==="
psql "$DSN" << 'SQL'
SELECT
    validation_status,
    specialist,
    count(*) AS count
FROM findings
WHERE case_id = 'net-scaffold-1778102586'
GROUP BY validation_status, specialist
ORDER BY validation_status, specialist;
SQL

echo ""
echo "=== Self-corrections succeeded vs failed ==="
psql "$DSN" << 'SQL'
SELECT
    succeeded,
    count(*) AS count
FROM self_corrections
GROUP BY succeeded;
SQL
