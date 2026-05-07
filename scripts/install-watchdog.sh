#!/usr/bin/env bash
# Install tailscaled-watchdog on the local host. Run with sudo.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

install -m 0755 "$HERE/tailscaled-watchdog.sh"      /usr/local/bin/tailscaled-watchdog.sh
install -m 0644 "$HERE/tailscaled-watchdog.service" /etc/systemd/system/tailscaled-watchdog.service
install -m 0644 "$HERE/tailscaled-watchdog.timer"   /etc/systemd/system/tailscaled-watchdog.timer
systemctl daemon-reload
systemctl enable --now tailscaled-watchdog.timer
echo "[+] tailscaled-watchdog installed; timer active."
systemctl list-timers tailscaled-watchdog --no-pager
