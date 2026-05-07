#!/usr/bin/env bash
# Build the find-evil-sleuth/sift podman image.
# Run on insa-dev-server (100.111.46.46) where podman is available.
#
# Usage: ./scripts/build-sift-image.sh [--no-cache]
#
# ~10 GB, ~30 min first time. Uses teamdfir/sift-cli v1.14.0-rc1
# against Ubuntu 22.04 in headless server mode.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${REPO_ROOT}/broker/tools"
CACHE_FLAG=""

if [[ "${1:-}" == "--no-cache" ]]; then
    CACHE_FLAG="--no-cache"
fi

echo "==> Building find-evil-sleuth/sift from sift.Dockerfile"
echo "    WARNING: first build takes ~30 min and ~10 GB disk."
START=$(date +%s)

podman build \
    ${CACHE_FLAG} \
    -t "find-evil-sleuth/sift:latest" \
    -f "${TOOLS_DIR}/sift.Dockerfile" \
    "${TOOLS_DIR}"

END=$(date +%s)
ELAPSED=$(( END - START ))
echo ""
echo "==> Build complete in ${ELAPSED}s"
echo ""
echo "==> Image listing:"
podman image ls find-evil-sleuth/sift

echo ""
echo "==> Smoke test: fls -V inside container:"
podman run --rm find-evil-sleuth/sift bash -c 'fls -V'
