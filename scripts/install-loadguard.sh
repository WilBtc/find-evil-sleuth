#!/usr/bin/env bash
# Install the loadguard timer on the local host. Run with sudo.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

install -m 0755 "$HERE/loadguard.sh"      /usr/local/bin/loadguard.sh
install -m 0644 "$HERE/loadguard.service" /etc/systemd/system/loadguard.service
install -m 0644 "$HERE/loadguard.timer"   /etc/systemd/system/loadguard.timer
systemctl daemon-reload
systemctl enable --now loadguard.timer
echo "[+] loadguard installed; firing every 60s."
systemctl list-timers loadguard --no-pager
