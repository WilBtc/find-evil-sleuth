#!/usr/bin/env bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth -c "SELECT count(*) FROM findings WHERE case_id LIKE 'lone-wolf-%' AND specialist='disk' AND validation_status='confirmed';"
