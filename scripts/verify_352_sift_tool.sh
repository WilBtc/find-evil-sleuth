#!/usr/bin/env bash
# Verify 3.5.2 acceptance criterion:
# mmls-sift is registered in tool_specs and routes through find-evil-sleuth/sift:latest
set -euo pipefail

DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth

echo "=== tool_specs row for mmls-sift ==="
psql "$DB" -c "SELECT tool, image, timeout_s, memory_mb, network FROM tool_specs WHERE tool = 'mmls-sift';"

echo ""
echo "=== Running mmls-sift via ./bin/sb against cases/mini/disk.img ==="
CASE_ID=sift-probe-$(date +%s)
./bin/sb exec --case "$CASE_ID" --tool mmls-sift --args '{"image":"/case/disk.img"}'
