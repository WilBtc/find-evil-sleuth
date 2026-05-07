# Emergency access — when Tailscale wedges

`tailscaled` can enter a state where `systemctl is-active` returns `active`
but the coordination-plane connection is dead, leaving the node "offline" in
the Tailscale admin panel and unreachable on its 100.x.x.x address.

## Recovery: jump via LAN-adjacent peer

`insa-server-2` (`100.94.21.11`) and `insa-dev-server` (`100.111.46.46`) sit on
the same LAN. When Tailscale path to one is down, the other can still reach it
on the LAN.

```bash
# Verify the wedge.
ping -c2 -W2 100.111.46.46            # ICMP fails over Tailscale
ssh -o ConnectTimeout=5 wil@100.111.46.46 echo ok   # also fails

# Reach the box via insa-server-2 jump host on the LAN.
ssh -J wil@100.94.21.11 wil@192.168.0.213 hostname
# or two-hop:
ssh wil@100.94.21.11 'ssh wil@192.168.0.213 hostname'
```

## Repair

Once on the box (via LAN), bounce the daemon:

```bash
sudo systemctl restart tailscaled
sleep 5
tailscale status | head            # Should show peers; you'll be reachable on 100.x within 30 s
```

If restart doesn't help, the next escalations (in order) are:

1. `sudo tailscale up --reset --auth-key=...` — fresh login (rare; only if auth key expired)
2. `sudo systemctl restart systemd-networkd` — DHCP / route refresh
3. Reboot

## Prevention

`scripts/tailscaled-watchdog.sh` runs every 5 min via systemd timer, pings a
peer with `tailscale ping`, and restarts tailscaled after 3 consecutive
failures. Install on every host with:

```bash
sudo ./scripts/install-watchdog.sh
```

Watchdog state is in `/run/tailscaled-watchdog.fails`, logs in journald:
`journalctl -u tailscaled-watchdog.service`.

## LAN topology cheat sheet

| Host | Tailscale | LAN | Notes |
|---|---|---|---|
| insa-dev-server | 100.111.46.46 | 192.168.0.213 | 32c/62GB; build host |
| insa-server-2 | 100.94.21.11 | 192.168.0.231 | 56c/125GB; LAN-adjacent jump |
| t-pad | 100.119.146.74 | (varies) | laptop, mobile |
| g1-avilion | 100.116.33.91 | (different LAN) | Avilion services |

Public IP of the dev/server LAN: 190.146.142.104 (NAT shared by both insa-dev-server
and insa-server-2).
