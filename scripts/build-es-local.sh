#!/usr/bin/env bash
# Build the evidence-store binary locally (run on insa-dev-server).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[build-es] Building evidence-store..."
cd "${REPO_ROOT}"
cargo build --release -p evidence-store 2>&1

echo "[build-es] Copying binary to bin/es..."
cp "${REPO_ROOT}/target/release/es" "${REPO_ROOT}/bin/es"
chmod +x "${REPO_ROOT}/bin/es"

echo "[build-es] Done."
