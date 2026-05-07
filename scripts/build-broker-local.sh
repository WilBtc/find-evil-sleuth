#!/usr/bin/env bash
# Build the broker binary locally (run on insa-dev-server).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[build-broker] Building broker..."
cd "${REPO_ROOT}"
cargo build --release -p sleuth-broker 2>&1

echo "[build-broker] Copying binary to bin/sb..."
cp "${REPO_ROOT}/target/release/sb" "${REPO_ROOT}/bin/sb"
chmod +x "${REPO_ROOT}/bin/sb"

echo "[build-broker] Done."
