#!/usr/bin/env bash
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
psql "$DB" -c "SELECT count(*) FROM findings WHERE case_id='lone-wolf-network' AND specialist='network';"
psql "$DB" -c "SELECT finding_id, claim FROM findings WHERE case_id='lone-wolf-network' AND specialist='network' ORDER BY finding_id;"
