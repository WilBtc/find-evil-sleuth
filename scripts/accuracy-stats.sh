#!/usr/bin/env bash
# Gather accuracy statistics from the sleuth DB for ACCURACY.md
DSN="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"

echo "=== 1. Overall validation status counts (all cases) ==="
psql "$DSN" << 'SQL'
SELECT
    validation_status,
    count(*) AS count
FROM findings
GROUP BY validation_status
ORDER BY validation_status;
SQL

echo ""
echo "=== 2. Status counts by case ==="
psql "$DSN" << 'SQL'
SELECT
    case_id,
    validation_status,
    count(*) AS count
FROM findings
GROUP BY case_id, validation_status
ORDER BY case_id, validation_status;
SQL

echo ""
echo "=== 3. Lone-wolf case summary ==="
psql "$DSN" << 'SQL'
SELECT
    validation_status,
    count(*) AS count
FROM findings
WHERE case_id LIKE '%lone-wolf%' OR case_id LIKE '%lw-%' OR case_id LIKE '%lonewolf%'
GROUP BY validation_status
ORDER BY validation_status;
SQL

echo ""
echo "=== 4. Cases in the DB ==="
psql "$DSN" << 'SQL'
SELECT case_id, created_at FROM cases ORDER BY created_at;
SQL

echo ""
echo "=== 5. Self-corrections (hallucinations caught by validator) ==="
psql "$DSN" << 'SQL'
SELECT
    sc.case_id,
    sc.finding_id,
    sc.old_claim,
    sc.new_claim,
    sc.reason,
    sc.created_at
FROM self_corrections sc
ORDER BY sc.created_at
LIMIT 20;
SQL

echo ""
echo "=== 6. Refuted findings (false positives) ==="
psql "$DSN" << 'SQL'
SELECT
    f.finding_id,
    f.case_id,
    f.specialist,
    f.claim,
    f.confidence,
    f.validation_status
FROM findings f
WHERE f.validation_status = 'refuted'
ORDER BY f.case_id, f.finding_id
LIMIT 20;
SQL

echo ""
echo "=== 7. Inconclusive findings ==="
psql "$DSN" << 'SQL'
SELECT
    f.finding_id,
    f.case_id,
    f.specialist,
    f.claim,
    f.confidence,
    f.validation_status
FROM findings f
WHERE f.validation_status = 'inconclusive'
ORDER BY f.case_id, f.finding_id
LIMIT 20;
SQL

echo ""
echo "=== 8. Validation runs summary ==="
psql "$DSN" << 'SQL'
SELECT
    case_id,
    count(*) AS total_runs,
    count(*) FILTER (WHERE verdict = 'confirmed') AS confirmed,
    count(*) FILTER (WHERE verdict = 'refuted')   AS refuted,
    count(*) FILTER (WHERE verdict = 'inconclusive') AS inconclusive
FROM validation_runs
GROUP BY case_id
ORDER BY case_id;
SQL

echo ""
echo "=== 9. Total findings per specialist ==="
psql "$DSN" << 'SQL'
SELECT
    specialist,
    count(*) AS total,
    count(*) FILTER (WHERE validation_status = 'confirmed')   AS confirmed,
    count(*) FILTER (WHERE validation_status = 'refuted')     AS refuted,
    count(*) FILTER (WHERE validation_status = 'inconclusive') AS inconclusive,
    count(*) FILTER (WHERE validation_status = 'pending')     AS pending
FROM findings
GROUP BY specialist
ORDER BY specialist;
SQL

echo ""
echo "=== 10. Validation history count ==="
psql "$DSN" << 'SQL'
SELECT count(*) AS validation_history_total FROM validation_history;
SQL
