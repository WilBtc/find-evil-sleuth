#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
pkill sleuth-saas 2>/dev/null || true
sleep 2
cp target/release/sleuth-saas bin/sleuth-saas
chmod +x bin/sleuth-saas
DATABASE_URL="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth" \
  RUST_LOG=info \
  nohup ./bin/sleuth-saas > /tmp/sleuth-saas.log 2>&1 &
echo "sleuth-saas PID: $!"
sleep 2
cat /tmp/sleuth-saas.log
