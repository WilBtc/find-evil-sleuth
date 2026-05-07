#!/usr/bin/env bash
# Build the broker binary on insa-dev-server and copy it back to bin/sb.
# Run from repo root on any machine with SSH access to 100.111.46.46.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_SERVER="wil@100.111.46.46"
REMOTE_REPO="/home/wil/projects/find-evil-sleuth"

echo "[build-broker] Syncing source to dev server..."
rsync -az --delete \
    --exclude target \
    --exclude '.git' \
    "${REPO_ROOT}/broker/" "${DEV_SERVER}:${REMOTE_REPO}/broker/"

echo "[build-broker] Building on dev server..."
ssh "${DEV_SERVER}" "cd ${REMOTE_REPO}/broker && cargo build --release 2>&1"

echo "[build-broker] Copying binary back..."
scp "${DEV_SERVER}:${REMOTE_REPO}/broker/target/release/sb" "${REPO_ROOT}/bin/sb"
chmod +x "${REPO_ROOT}/bin/sb"

echo "[build-broker] Done. Binary at bin/sb"
