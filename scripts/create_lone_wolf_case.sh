#!/usr/bin/env bash
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
psql "$DB" -c "INSERT INTO cases (case_id, name, status) VALUES ('lone-wolf-disk', 'LoneWolf 2018 Disk Analysis', 'triage') ON CONFLICT (case_id) DO UPDATE SET name='LoneWolf 2018 Disk Analysis';"
psql "$DB" -c "SELECT case_id, name, status FROM cases WHERE case_id='lone-wolf-disk';"
