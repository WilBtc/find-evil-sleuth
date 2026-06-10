#!/usr/bin/env bash
# fetch-sift.sh — Build the find-evil-sleuth/sift-full image from the FULL SANS SIFT
# Workstation distribution.
#
# PRIMARY PATH (current SIFT) — official SANS OVA -> rootfs -> podman import:
#   The SANS SIFT Workstation OVA is gated behind an email form at
#   https://www.sans.org/tools/sift-workstation/ . Download it (e.g. sift-2026-04-22.ova)
#   into $CACHE, then this script extracts the root filesystem with libguestfs
#   (which handles the LVM ubuntu-vg/ubuntu-lv root natively — a plain loop-mount or
#   ova-to-docker's direct mount fails on LVM) and imports it as a podman image.
#
# FALLBACK PATH (no OVA) — pull the maintained SIFT+REMnux bundle:
#   podman pull docker.io/digitalsleuth/sift-remnux:latest
#   podman tag  docker.io/digitalsleuth/sift-remnux:latest find-evil-sleuth/sift-full:remnux-2024.10.19
#   (older, REMnux-bundled; use only if the official OVA is unavailable)
#
# Run on a host with podman + libguestfs (virt-tar-out) + >=40 GB free.
set -euo pipefail

CACHE="${SIFT_CACHE:-/var/sleuth/sift-cache}"
OVA="${1:-$CACHE/sift-2026-04-22.ova}"
IMG="find-evil-sleuth/sift-full"
VER="$(basename "$OVA" .ova | sed 's/^sift-//; s/-/./g')"   # sift-2026-04-22.ova -> 2026.04.22

[[ -f "$OVA" ]] || { echo "!! OVA not found: $OVA
   Download the current SIFT OVA from https://www.sans.org/tools/sift-workstation/
   into $CACHE, or run the FALLBACK path documented at the top of this script."; exit 1; }

echo "==> Extracting disk from OVA"
mkdir -p "$CACHE/ova-extract"
tar -xf "$OVA" -C "$CACHE/ova-extract"
DISK="$(ls "$CACHE/ova-extract"/*.vmdk | head -1)"

echo "==> Inspecting filesystems (expect an LVM root: ubuntu-vg/ubuntu-lv)"
sudo virt-filesystems -a "$DISK" --long --all

echo "==> Streaming root filesystem out with libguestfs (handles LVM)"
sudo virt-tar-out -a "$DISK" / "$CACHE/sift-rootfs.tar"

echo "==> Importing rootfs as $IMG:$VER"
# ignore_chown_errors in storage.conf maps the image's out-of-range snap UIDs to root
podman import \
  --change 'CMD ["/bin/bash"]' \
  --change 'ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
  "$CACHE/sift-rootfs.tar" "$IMG:$VER"
podman tag "$IMG:$VER" "$IMG:latest"

echo "==> Acceptance check"
SIZE_GB=$(( $(podman image inspect "$IMG:latest" --format '{{.Size}}') / 1000000000 ))
echo "    image size: ${SIZE_GB} GB (must be >5)"
[[ "$SIZE_GB" -gt 5 ]] || { echo "!! image too small — not the full SIFT"; exit 1; }
podman run --rm "$IMG:latest" bash -lc 'fls -V; vol --help >/dev/null && echo "vol: Volatility 3 present"; log2timeline.py --version'

echo "==> Done. $IMG:latest is the full SANS SIFT $VER distribution."
