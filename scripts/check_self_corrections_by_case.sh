#!/usr/bin/env bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth << 'SQL'
SELECT case_id, COUNT(*) AS sc_count
FROM self_corrections
GROUP BY case_id
ORDER BY sc_count DESC
LIMIT 10;
SQL
