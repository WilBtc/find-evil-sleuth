#!/usr/bin/env bash
# Install the already-built broker binary to bin/sb.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp "${REPO_ROOT}/target/release/sb" "${REPO_ROOT}/bin/sb"
chmod +x "${REPO_ROOT}/bin/sb"
echo "Installed bin/sb ($(du -sh "${REPO_ROOT}/bin/sb" | cut -f1))"
