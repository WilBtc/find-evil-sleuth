#!/usr/bin/env bash
# Build all per-tool podman images for find-evil-sleuth.
# Run this on insa-dev-server (100.111.46.46) where podman is available.
#
# Usage: ./scripts/build-tool-images.sh [--no-cache]
#
# Images built:
#   find-evil-sleuth/sleuthkit   - fls, mmls, icat, tsk_recover, blkls
#   find-evil-sleuth/volatility3 - vol3 memory forensics
#   find-evil-sleuth/tshark      - tshark, editcap, mergecap, capinfos
#   find-evil-sleuth/plaso       - log2timeline.py, psort.py
#   find-evil-sleuth/zeek        - zeek + ET-Open intel feed
#   find-evil-sleuth/suricata    - suricata + ET-Open rules
#   find-evil-sleuth/yara        - yara pattern matcher

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${REPO_ROOT}/broker/tools"
CACHE_FLAG=""

if [[ "${1:-}" == "--no-cache" ]]; then
    CACHE_FLAG="--no-cache"
fi

build() {
    local name="$1"
    local dockerfile="$2"
    echo "==> Building find-evil-sleuth/${name} from ${dockerfile}"
    podman build \
        ${CACHE_FLAG} \
        -t "find-evil-sleuth/${name}:latest" \
        -f "${TOOLS_DIR}/${dockerfile}" \
        "${TOOLS_DIR}"
    echo "    OK: find-evil-sleuth/${name}"
}

build "sleuthkit"   "sleuthkit.Dockerfile"
build "volatility3" "volatility3.Dockerfile"
build "tshark"      "tshark.Dockerfile"
build "plaso"       "plaso.Dockerfile"
build "zeek"        "zeek.Dockerfile"
build "suricata"    "suricata.Dockerfile"
build "yara"        "yara.Dockerfile"

echo ""
echo "==> All images built. Listing:"
podman image ls "find-evil-sleuth/*"
