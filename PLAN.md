# find-evil-sleuth — Implementation Plan

**Hackathon:** SANS "FIND EVIL!" on Devpost
**Submission deadline:** 2026-06-15 23:45 EDT
**Today:** 2026-05-06 → **5.5 weeks** runway
**Repo:** Gitea `wil/find-evil-sleuth` (mirror to GitHub at the end)
**License:** Apache-2.0 (judges require MIT or Apache-2.0)

## Locked decisions

| Decision | Choice |
|---|---|
| Agentic framework | Claude Code (subagents + skills + hooks + ADW) |
| Tool surface | Skills + Rust CLIs only — **no MCP** |
| Reasoning loop | `claude --print` subprocess driven by ADW |
| Evidence depth | **disk + memory + network** (3 deep specialists) |
| Audit / memory substrate | **Postgres 17** with full plugin stack (see below) |
| Container runtime | rootless podman with seccomp + read-only evidence mount |
| Self-correction demo | **corrupt evidence + tool crash** (both, in one investigation) |
| Repo host | Gitea primary (`100.94.21.11:3005`), GitHub mirror at submission |

## Postgres "agentic substrate" — extension stack

One Postgres 17 instance, port 5532 (allocated via `port-registry`), runs in `docker/postgres/`:

| Extension | Purpose in agent |
|---|---|
| `pgvector` | Embeddings of artifacts, log lines, IOCs — semantic dedup across iterations |
| `apache_age` | Attack graph (process → file → registry → network) — Cypher queries |
| `timescaledb` | Hypertable on `tool_calls` for execution-log telemetry |
| `pg_cron` | In-DB re-validation scheduler (replaces external cron) |
| `pg_partman` | Partition management for `artifacts` blobstore over time |
| `pg_trgm` | Fuzzy match on filenames, hostnames, IOCs |
| `pgcrypto` | BLAKE3-equivalent hashing + Merkle root chaining |
| `pg_stat_statements` | Self-observability of agent query patterns |
| `pgaudit` | Required: tamper-evident audit log of every DB mutation |
| `pg_jsonschema` | Validate tool-call args before broker execution |
| `pg_graphql` | Optional read-only GraphQL surface for the report viewer |

Bootstrapped from `docker/postgres/init.sql`. Schema in `evidence-store/schema.sql`.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  claude --print (Sonnet 4.6 / Opus 4.7 for validator + judge)    │
│            ↓ subagents: triage / disk / memory / net / val / narr│
└─────┬──────────────────────────────────────────────────┬─────────┘
      │ Bash hook: only sleuth-broker / evidence-store    │
      ▼                                                    ▼
┌──────────────────┐                            ┌────────────────────┐
│ sleuth-broker    │── podman run --rm ──▶ tool │ evidence-store     │
│ (Rust)           │   (rootless, seccomp,      │ (Rust → Postgres)  │
│ allowlist+caps   │    ro evidence mount,       │ tool_calls,        │
│                  │    tmpfs scratch)           │ artifacts(blake3), │
│                  │                             │ findings, merkle,  │
│                  │  stdout → blob hash ───────▶│ embeddings(vec),   │
└──────────────────┘                             │ graph(AGE)         │
      ▲                                          └─────────┬──────────┘
      │                                                    │
┌─────┴──────────┐                                ┌────────▼─────────┐
│ agent-obs:8910 │◀── Phase A hook events ────────│ pg_cron: every    │
│ (existing)     │                                │  N min revalidate │
└────────────────┘                                └───────────────────┘
```

## Self-correction demo scenario (for the video)

Single investigation against the `LoneWolf` SANS dataset, scripted to hit both:

1. **Tool crash** — disk-specialist invokes `vol3 windows.malfind` against a memory image with a deliberately mis-stated profile. Volatility errors. Validator detects non-zero exit + empty findings. Retry agent re-runs `vol3 windows.info`, derives correct profile, re-invokes malfind successfully. **One self-correction visible.**
2. **Corrupt evidence** — network-specialist invokes `tshark -r evil.pcap`. We pre-truncate the pcap to simulate corruption. tshark fails on packet N. Agent detects, switches to `editcap -E 0 → editcap -F pcap` recovery flow, completes analysis on recovered slice, narrator notes "partial" confidence on affected findings. **Second self-correction, with confidence-tier downgrade visible.**

Both flows emit the same structured retry pattern (Phase G close-the-loops analyzer), so judges see consistent agent behavior, not ad-hoc patches.

## Reuse from existing L5 stack

- `agent-obs.service` :8910 → execution log artifact
- Phase B PostToolUse validator → findings re-run validator
- `adw` Rust CLI + `best_of_n.py` → self-correction outloop
- `verification-before-completion` skill → enforce citation-before-claim
- `systematic-debugging` skill → investigation reasoning template
- `parallel-agents` skill → fan-out per evidence chunk
- `port-registry` → :5532 (postgres), :8930 (broker), :8931 (evidence-store HTTP)
- `claude --print` subprocess pattern (`feedback_claude_code_subprocess_for_llm`)

## Milestones

### Week 1 (May 6–12) — substrate
- [ ] Init Gitea repo `wil/find-evil-sleuth`, Apache-2.0 LICENSE, README skeleton
- [ ] `docker/postgres/Dockerfile` + `init.sql` with all 11 extensions
- [ ] `evidence-store/` Rust crate: schema, BLAKE3 hashing, Merkle chain, `cite` CLI
- [ ] `sleuth-broker/` Rust crate: tool allowlist, podman exec, seccomp profile, schema validation via pg_jsonschema
- [ ] Bash hook in `.claude/settings.json` blocking non-broker shell calls
- [ ] Smoke test: agent runs `tsk_recover` via broker, finding lands in Postgres, `evidence-store cite` returns trace

### Week 2 (May 13–19) — specialists
- [ ] Skill `dfir-triage` (evidence classifier + plan)
- [ ] Skill + subagent `disk-forensics` (sleuthkit, plaso, fls, icat, mmls, yara)
- [ ] Skill + subagent `memory-forensics` (volatility3 plugin set: pslist, pstree, malfind, netscan, cmdline, dlllist, handles, svcscan)
- [ ] Skill + subagent `network-forensics` (zeek, suricata + ET-Open rules, tshark, editcap, ngrep)
- [ ] AGE graph schema: nodes (process, file, registry_key, network_endpoint, user), edges (spawned, wrote, connected_to, accessed)
- [ ] pgvector embeddings for IOC dedup (`text-embedding-3-small` via `claude --print` is fine)

### Week 3 (May 20–26) — validator + narrator + outloop
- [ ] Skill + subagent `findings-validator` (re-runs claim, marks confirmed/refuted/inconclusive)
- [ ] Skill + subagent `ir-narrator` (assembles report, `[F-NNN]` citations)
- [ ] ADW driver `adws/investigate.py` — orchestrates triage → fan-out → validate → narrate, persistent loop until validator queue empty
- [ ] pg_cron: re-validate findings older than 1h
- [ ] Best-of-N judge for narrator output (Opus 4.7)

### Week 4 (May 27–Jun 2) — sample evidence + corrupt/crash injection
- [ ] Pull SANS LoneWolf or Magnet CTF sample; document provenance in `evidence-samples/README.md`
- [ ] Build `evidence-samples/inject-corruption.sh` to deterministically truncate pcap + mis-state vol3 profile
- [ ] End-to-end run: agent investigates, hits both failure modes, recovers, emits report
- [ ] Tune until self-correction is reliable + visible in obs event stream

### Week 5 (Jun 3–9) — submission deliverables
- [ ] Architecture diagram (excalidraw skill → SVG in `docs/architecture.svg`)
- [ ] Accuracy Report (`docs/ACCURACY.md`) — known false positives, missed artifacts, hallucinations caught
- [ ] Evidence Dataset Documentation (`docs/EVIDENCE.md`)
- [ ] Agent Execution Logs export script: dumps obs events + tool_calls hypertable to NDJSON
- [ ] README install: `git clone && docker compose up -d && ./scripts/investigate.sh evidence-samples/lone-wolf/`
- [ ] Demo screencast: terminal-only, audio narration, ≤5 min, both self-corrections on camera

### Week 6 (Jun 10–14) — buffer + submission
- [ ] Mirror to GitHub, ensure Apache-2.0 visible in About
- [ ] Devpost submission form: video URL, repo URL, text description
- [ ] Submit by Jun 15 23:45 EDT (target Jun 13 to leave buffer)

## Risk register

| Risk | Mitigation |
|---|---|
| Volatility3 profile detection unreliable on arbitrary memory dumps | Stick to documented SANS sample images |
| podman seccomp blocks legit forensics syscall | Profile derived from baseline run, allowlist drift |
| Postgres extension conflicts (timescale + age + cron) | Lock to known-good versions in Dockerfile, CI smoke test |
| Demo video rerecord cost | Pre-script the investigation; don't ad-lib |
| Hub IP drift bites again (`feedback_hub_ip_drift`) | All addresses via env vars from `.env` only |

## Out of scope (explicit)

- Live-response MCP endpoints (deferred — adds attack surface, doesn't help judging)
- Cloud forensics (AWS/Azure)
- Mobile forensics
- Multi-tenant / auth — single-investigator local tool
- GitHub primary mirror until repo is ship-ready
