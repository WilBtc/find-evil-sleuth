#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
pkill sleuth-saas 2>/dev/null || true
sleep 1
BIN="./bin/sleuth-saas"
if [ ! -x "$BIN" ]; then
  BIN="./target/debug/sleuth-saas"
fi
DATABASE_URL="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth" \
  RUST_LOG=info \
  nohup "$BIN" > /tmp/sleuth-saas.log 2>&1 &
echo "sleuth-saas PID: $!"
sleep 2
cat /tmp/sleuth-saas.log
