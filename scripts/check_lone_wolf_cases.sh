#!/usr/bin/env bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth << 'SQL'
SELECT case_id, name, status, started_at
FROM cases
ORDER BY started_at DESC;
SQL
