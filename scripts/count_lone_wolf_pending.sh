#!/usr/bin/env bash
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
psql "$DB" -c "SELECT finding_id, specialist, validation_status, left(claim, 60) as claim_preview FROM findings WHERE case_id='lone-wolf-disk' ORDER BY finding_id;"
psql "$DB" -c "SELECT validation_status, count(*) FROM findings WHERE case_id='lone-wolf-disk' GROUP BY validation_status;"
