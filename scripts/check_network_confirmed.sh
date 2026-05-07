#!/usr/bin/env bash
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
echo "=== Acceptance criterion check ==="
psql "$DB" -c "SELECT count(*) FROM findings WHERE case_id LIKE 'lone-wolf-%' AND specialist='network' AND validation_status='confirmed';"
echo ""
echo "=== All lone-wolf network findings ==="
psql "$DB" -c "SELECT finding_id, validation_status, case_id FROM findings WHERE case_id LIKE 'lone-wolf-%' AND specialist='network' ORDER BY finding_id;"
