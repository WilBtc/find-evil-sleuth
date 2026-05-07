#!/usr/bin/env bash
DSN="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"

echo "=== cases schema ==="
psql "$DSN" -c "\d cases"

echo ""
echo "=== self_corrections schema ==="
psql "$DSN" -c "\d self_corrections"

echo ""
echo "=== validation_runs schema ==="
psql "$DSN" -c "\d validation_runs"

echo ""
echo "=== cases list ==="
psql "$DSN" -c "SELECT * FROM cases LIMIT 20;"

echo ""
echo "=== self_corrections data ==="
psql "$DSN" -c "SELECT * FROM self_corrections LIMIT 20;"

echo ""
echo "=== validation_runs sample ==="
psql "$DSN" -c "SELECT * FROM validation_runs LIMIT 10;"
