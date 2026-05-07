#!/usr/bin/env bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth << 'SQL'
SELECT case_id, COUNT(*) AS tc_count
FROM tool_calls
GROUP BY case_id
ORDER BY tc_count DESC
LIMIT 10;
SQL
