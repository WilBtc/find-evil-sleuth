# 08 · Risk Register & Rollback

| # | Risk | Likelihood | Impact | Mitigation | Rollback / Plan-B |
|---|---|---|---|---|---|
| R1 | Postgres extension version conflict (timescaledb + age + cron) | M | High | Lock all versions in Dockerfile build args; CI smoke job rebuilds image and runs `\dx` check | Pin to known-good combo from compose stack on g1; if AGE breaks, fall back to relational graph (path closures via recursive CTE) — already have schema |
| R2 | podman seccomp blocks legitimate forensics syscall | H | Med | Per-tool seccomp override file; baseline strace run during Phase 1 | Per-tool override registered in `tool_specs.seccomp_profile`; documented exceptions |
| R3 | vol3 windows.malfind unreliable on arbitrary memory | M | High | Stick to LoneWolf for demo; document supported profiles only | Pre-compute correct profile, store in repo; demo case is fixed |
| R4 | tshark tolerates truncated pcap → demo #2 doesn't fire | M | High | Truncate deeper, assert non-zero exit in Phase 4 | Use `tcpdump -r` instead (stricter parser) as fallback recovery path |
| R5 | Hub IP drift bites again (`feedback_hub_ip_drift.md`) | L | Med | All addresses via `.env` only, single source of truth | Sed-fix script in `scripts/fix-ips.sh` |
| R6 | Anthropic rate-limit on insa-server-2 mid-run | M | High | Mirror runs to g1 (separate account), proven pattern | Switch driver to g1 with `--remote-host g1.tail` flag |
| R7 | YouTube processing delay before deadline | M | High | Upload final take ≥24h before deadline | Vimeo backup upload as plan B |
| R8 | Devpost form drops a required field at submit time | L | High | Submit Jun 13, leave 48h buffer | Buffer is the rollback |
| R9 | Container escape via prompt-injected evidence (e.g. crafted filename `; rm -rf` or yara rule with shell escape) | L | Critical | Architectural guardrail + path-pattern args schema + seccomp + cap-drop ALL + read-only mount | Red-team test in Phase 4 with adversarial filename + log content; document outcome in ACCURACY.md as a security feature |
| R10 | Postgres on host conflicts with port 5532 | L | Low | port-registry reserved 5532 in compose; check on Phase 1 | Move port via env var |
| R11 | podman rootless setup fails on judges' machine | M | Med | `docker compose` works as runtime substitute (same images); document both | Compose path is the documented one; podman is internal |
| R12 | Apache AGE write performance for many MERGE per finding | M | Med | Batch graph mutations per specialist | Skip graph for large cases, fall back to recursive CTE in evidence-store |
| R13 | Token budget overrun (Opus validator passes too expensive) | M | Med | obs cost guardian with $30/case hard cap | Drop validator to Sonnet 4.6 with double-pass; document as tradeoff in ACCURACY.md |
| R14 | One specialist takes >45 min, blocks demo | M | High | Per-specialist timeout in ADW + watchdog | Skip and mark `failed_at_timeout`; narrator covers what's confirmed |
| R15 | Best-of-N narrator never produces citation-clean candidate | L | Med | Stop hook re-runs; cap at 6 candidates | Hand-edit during dev iterations; document as iteration gap |

## Kill switches

- `touch ~/.adw-pause` — already wired into your scheduler; pauses any new ADW invocations.
- `docker compose down` — full halt.
- Postgres has `pgaudit` so all writes are logged; can replay from logs if a bad commit corrupts state.

## Dry-run gates (no skipping)

- **Gate A (end Week 1):** broker smoke test green, hook blocks rm/curl, all 11 extensions installed.
- **Gate B (end Week 2):** each specialist solo run produces ≥10 findings against mini-evidence.
- **Gate C (end Week 3):** end-to-end unattended run < 30 min.
- **Gate D (end Week 4):** three consecutive clean runs against LoneWolf with both self-corrections.
- **Gate E (mid Week 5):** one full clone-to-report dry-run on a fresh VM.

Missing any gate by date → reduce scope (drop network specialist first; demo with disk+memory only). Don't slip the deadline.
