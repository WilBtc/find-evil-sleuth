#!/usr/bin/env bash
# Check memory findings for lone-wolf case

DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth

echo "=== Memory findings count by validation status ==="
psql "$DB" -c "
SELECT validation_status, count(*)
FROM findings
WHERE case_id LIKE 'lone-wolf-%' AND specialist='memory'
GROUP BY validation_status
ORDER BY validation_status;
"

echo ""
echo "=== Total confirmed memory findings (acceptance criteria: >= 20) ==="
psql "$DB" -c "
SELECT count(*) as confirmed_count
FROM findings
WHERE case_id LIKE 'lone-wolf-%' AND specialist='memory' AND validation_status='confirmed';
"

echo ""
echo "=== Memory findings details ==="
psql "$DB" -c "
SELECT finding_id, claim, mitre_technique, validation_status
FROM findings
WHERE case_id LIKE 'lone-wolf-%' AND specialist='memory'
ORDER BY finding_id;
"