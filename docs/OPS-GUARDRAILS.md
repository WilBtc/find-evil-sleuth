# Host Guardrails (insa-dev-server)

Added 2026-06-12 after a heavy 20 GB image carve wedged the host (CPU/IO/memory
saturation made it unresponsive on every network path). Layered protection so a
runaway forensic/build process can never take the box down again:

| Guard | What it does | Where |
|-------|--------------|-------|
| **earlyoom** | Userspace OOM killer — acts on memory pressure (<6% mem & swap) *before* the kernel hangs. Protects systemd/sshd/postgres/tailscaled; prefers to kill heavy hogs (img_cat, bulk_extractor, strings, ewfexport, cargo). | `systemctl status earlyoom`, `/etc/default/earlyoom` |
| **loadguard** | Kills the highest-CPU non-essential process when 1-min load > NCPU×2 (was ×4=128, never fired at the wedge load of ~15-30). | `journalctl -t loadguard`, `/etc/systemd/system/loadguard.service.d/10-threshold.conf` |
| **sleuth.slice** | The find-evil-sleuth pipeline runs in a cgroup-v2 slice capped at MemoryMax=24G, CPUQuota=1600% (16 cores). | `~/.config/systemd/user/sleuth.slice`; `scripts/investigate.sh` wraps the run in it (linger enabled so it persists). |
| **broker limits** | Each forensic tool container already runs with `--cpus 4`, `--memory` (per `tool_specs`), `--pids-limit`. | `broker/src/podman.rs` |

**Operator rule:** never run a direct `img_cat`/`bulk_extractor`/`strings` carve over a
full disk outside the broker without a memory cap. Use the pipeline (capped slice) or
`systemd-run --user --scope --slice=sleuth.slice -p MemoryMax=8G <cmd>`.
