#!/usr/bin/env bash
# fetch-sift.sh — Acquire the FULL SANS SIFT distribution as a podman image.
#
# Backlog 5.4.1. The cached SIFT OVA VMDK download was truncated/corrupt
# ("Invalid footer"), so this uses Path 2: pull the maintained SIFT+REMnux
# bundle from digitalsleuth (the current SIFT maintainer), retag, and add a
# thin compatibility layer via broker/tools/sift-full.Dockerfile.
#
# Run on insa-dev-server (podman available, >=20 GB free).
#   ./scripts/fetch-sift.sh
set -euo pipefail

BASE="docker.io/digitalsleuth/sift-remnux:latest"
SRC_TAG="remnux-2024.10.19"          # base publish date, for the versioned tag
IMG="find-evil-sleuth/sift-full"

echo "==> Preflight: rootless subuid range must cover the image's high UIDs (~88578)"
RANGE=$(grep "^$USER:" /etc/subuid | cut -d: -f3 || echo 0)
if [[ "${RANGE:-0}" -lt 100000 ]]; then
  echo "!! subuid range for $USER is ${RANGE:-unset}; the base image needs >=100000."
  echo "   Fix: sudo sed -i 's/^$USER:[0-9]*:[0-9]*/$USER:100000:200000/' /etc/subuid /etc/subgid && podman system migrate"
  exit 1
fi

echo "==> Pulling base distribution: $BASE (~7.4 GB compressed / ~15 GB on disk)"
podman pull "$BASE"

echo "==> Tagging provenance + building compat layer"
podman tag "$BASE" "$IMG:$SRC_TAG"
podman build -t "$IMG:latest" -f broker/tools/sift-full.Dockerfile broker/tools

echo "==> Acceptance check"
SIZE_BYTES=$(podman image inspect "$IMG:latest" --format '{{.Size}}')
SIZE_GB=$(( SIZE_BYTES / 1000000000 ))
echo "    image size: ${SIZE_GB} GB (must be >5)"
[[ "$SIZE_GB" -gt 5 ]] || { echo "!! image too small — not the full SIFT"; exit 1; }
podman run --rm "$IMG:latest" bash -lc 'fls -V; vol -V; log2timeline.py --version'

echo "==> Done. $IMG:latest is the full SIFT/REMnux distribution."
