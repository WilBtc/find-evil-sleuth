#!/usr/bin/env bash
# Build the sleuth-saas binary and (optionally) regenerate Tailwind CSS.
# Usage: ./scripts/build-saas.sh [--release]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAAS_DIR="${REPO_ROOT}/saas"
STATIC_DIR="${SAAS_DIR}/static"
PROFILE="${1:---release}"

echo "[build-saas] Building saas crate (profile: ${PROFILE})..."
cd "${REPO_ROOT}"
cargo build -p saas --release 2>&1

echo "[build-saas] Copying binary to bin/sleuth-saas..."
mkdir -p "${REPO_ROOT}/bin"
cp "${REPO_ROOT}/target/release/sleuth-saas" "${REPO_ROOT}/bin/sleuth-saas"
chmod +x "${REPO_ROOT}/bin/sleuth-saas"

# Regenerate Tailwind CSS if standalone binary is available.
TAILWIND_BIN="${REPO_ROOT}/bin/tailwindcss"
if [ -x "${TAILWIND_BIN}" ]; then
    echo "[build-saas] Regenerating Tailwind CSS..."
    mkdir -p "${STATIC_DIR}"
    "${TAILWIND_BIN}" \
        --input "${SAAS_DIR}/styles.in.css" \
        --output "${STATIC_DIR}/styles.css" \
        --minify
    echo "[build-saas] styles.css written."
else
    echo "[build-saas] tailwindcss not found at bin/tailwindcss — skipping CSS regen (pre-built styles.css used)."
fi

echo "[build-saas] Done. Binary at bin/sleuth-saas"
