#!/usr/bin/env bash
# tailscaled-watchdog
#
# Tailscale's daemon can wedge: `systemctl is-active` says "active", but the
# coordination-plane connection silently dies and peers see the node as
# offline.  Recovery is just a daemon restart, but only if something notices.
#
# This script: ping a known-up peer with `tailscale ping`. On N consecutive
# failures, restart tailscaled.  Counter persists in /run so a single transient
# blip doesn't trigger a restart.
#
# Run from a systemd timer every 5 min.  Logs via systemd-journal (stderr).

set -euo pipefail

PEER="${WATCHDOG_PEER:-}"
[[ -z $PEER ]] && {
    case "$(hostname)" in
        insa-dev-server) PEER=100.94.21.11 ;;     # → insa-server-2
        insa-server-2)   PEER=100.111.46.46 ;;    # → insa-dev-server
        t-pad|T-Pad)     PEER=100.94.21.11 ;;     # → insa-server-2
        *)               PEER=100.94.21.11 ;;     # default to insa-server-2
    esac
}

STATE=/run/tailscaled-watchdog.fails
THRESHOLD="${WATCHDOG_THRESHOLD:-3}"

fails=0
[[ -f $STATE ]] && fails=$(cat "$STATE" 2>/dev/null || echo 0)

# Use tailscale's own path-aware ping (1 attempt, 3s timeout).
if tailscale ping --c 1 --timeout 3s "$PEER" >/dev/null 2>&1; then
    if [[ $fails -gt 0 ]]; then
        echo "watchdog: peer $PEER reachable again after $fails failures" >&2
    fi
    rm -f "$STATE"
    exit 0
fi

fails=$(( fails + 1 ))
echo "$fails" > "$STATE"
echo "watchdog: peer $PEER unreachable (fail $fails/$THRESHOLD)" >&2

if [[ $fails -ge $THRESHOLD ]]; then
    echo "watchdog: threshold reached, restarting tailscaled" >&2
    systemctl restart tailscaled
    rm -f "$STATE"
    # Give it a moment, then re-probe to leave clean state for next tick.
    sleep 5
    if tailscale ping --c 1 --timeout 5s "$PEER" >/dev/null 2>&1; then
        echo "watchdog: tailscaled restarted, peer reachable" >&2
    else
        echo "watchdog: tailscaled restarted, peer STILL unreachable — escalate" >&2
        exit 1
    fi
fi
