# find-evil-sleuth — Master Plan

> Deep build plan for a Level-5 agentic DFIR system on SIFT, built with Claude Code + skills/CLI + an agentic Postgres substrate. Optimized to win the six SANS "FIND EVIL!" judging criteria.

**Deadline:** 2026-06-15 23:45 EDT · **Today:** 2026-05-06 · **Runway:** 5.5 weeks
**Repo:** `wil/find-evil-sleuth` on Gitea (`100.94.21.11:3005`) — GitHub mirror at submission
**License:** Apache-2.0 · **Branching:** `main` only, feature branches per phase

## 1. Win condition (judging criteria → design move)

| # | Criterion | Winning move |
|---|---|---|
| 1 | Autonomous Execution Quality | ADW outloop + best-of-N + Phase G structured retry; persistent loop driven by `pg_cron` (substrate is itself agentic) |
| 2 | IR Accuracy | Validator subagent re-runs every claim; confirmed/refuted/inconclusive tier; pgvector dedup of repeat findings |
| 3 | Breadth × Depth | Three deep specialists (disk, memory, network) with full SIFT toolchain; depth > breadth |
| 4 | Constraint Implementation | **Architectural** guardrails: Bash PreToolUse hook + Rust broker + rootless podman + seccomp + ro evidence mount + pg_jsonschema arg validation |
| 5 | Audit Trail | Postgres BLAKE3 content-addressed `artifacts`, Merkle-chained `tool_calls`, `findings.tool_call_id` FK, `evidence-store cite <F-ID>` returns full trace in <100ms |
| 6 | Usability & Documentation | One-command install (`docker compose up -d && ./scripts/investigate.sh ./case/`), excalidraw arch diagram, README with copy-paste examples |

**Differentiators no other team will have:**
- Architectural sandbox (broker + hook), not a system prompt
- Postgres-as-agentic-substrate — judges can run live `SELECT` during demo
- Apache AGE attack graph queryable in Cypher
- pgvector dedup means longer investigations don't re-pay for repeat artifacts

## 2. System architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  ADW driver: adws/investigate.py                                    │
│   spawns: claude --print --model sonnet-4-6 (subagents per case)    │
│   judge:  claude --print --model opus-4-7  (validator + best-of-N)  │
└──────┬─────────────────────────────────────────────────┬────────────┘
       │ Bash hook (PreToolUse): allow only ./bin/sb,    │
       │ ./bin/es, awk/grep/jq on broker output.         │
       ▼                                                  ▼
┌──────────────────────┐                       ┌─────────────────────────┐
│ sleuth-broker (sb)   │── podman run ──▶ tool │ evidence-store (es)     │
│ Rust, ~800 LOC       │   rootless, seccomp,  │ Rust, ~600 LOC          │
│ - schema validate    │   readonly evidence,  │ - blake3 hash           │
│ - allowlist          │   tmpfs scratch,      │ - merkle chain          │
│ - cgroup limits      │   no-net (default)    │ - pg pool (sqlx)        │
│ - timeout            │                       │ - cite / search / graph │
└─────────┬────────────┘                       └────────┬────────────────┘
          │                                             │
          └──────────────► Postgres 17 ◀────────────────┘
                          extensions: pgvector, apache_age, timescaledb,
                          pg_cron, pg_partman, pg_trgm, pgcrypto,
                          pg_stat_statements, pgaudit, pg_jsonschema, pg_graphql
                                       ▲
                                       │ pg_cron jobs:
                                       │  - revalidate findings >1h old
                                       │  - vacuum hypertables
                                       │  - merkle root rollup hourly
                                       │
┌──────────────────────┐               │
│ agent-obs :8910      │◀──────────────┘ via PostToolUse hook
│ (existing service)   │   posts every tool_call_id to obs
└──────────────────────┘
```

## 3. Repository layout

```
find-evil-sleuth/
├── README.md                       # one-command install + demo
├── LICENSE                         # Apache-2.0
├── PLAN.md                         # exec summary (already exists)
├── plans/                          # this dir
│   ├── 00-master-plan.md
│   ├── 01-postgres-substrate.md
│   ├── 02-broker-design.md
│   ├── 03-evidence-store-design.md
│   ├── 04-subagents-and-skills.md
│   ├── 05-adw-outloop.md
│   ├── 06-self-correction-demos.md
│   ├── 07-submission-deliverables.md
│   └── 08-risk-and-rollback.md
├── docker/
│   ├── compose.yaml                # postgres + obs sidecar
│   └── postgres/
│       ├── Dockerfile              # bookworm + extensions
│       ├── init.sql                # CREATE EXTENSION + schema
│       └── pg_hba.conf
├── broker/                         # Rust crate `sleuth-broker`
│   ├── Cargo.toml
│   ├── src/{main.rs,allowlist.rs,podman.rs,seccomp.rs,schema.rs}
│   ├── seccomp/sleuth.json
│   └── tools/                      # per-tool podman images
│       ├── sleuthkit.Dockerfile
│       ├── volatility3.Dockerfile
│       ├── plaso.Dockerfile
│       ├── zeek.Dockerfile
│       ├── suricata.Dockerfile
│       └── tshark.Dockerfile
├── evidence-store/                 # Rust crate `evidence-store`
│   ├── Cargo.toml
│   ├── src/{main.rs,db.rs,merkle.rs,cite.rs,graph.rs,vector.rs}
│   └── migrations/                 # sqlx migrations
├── .claude/
│   ├── settings.json               # hooks: PreToolUse + PostToolUse + Stop
│   ├── agents/find-evil/
│   │   ├── triage.md
│   │   ├── disk-specialist.md
│   │   ├── memory-specialist.md
│   │   ├── network-specialist.md
│   │   ├── validator.md
│   │   └── narrator.md
│   ├── skills/find-evil/
│   │   ├── dfir-triage/SKILL.md
│   │   ├── disk-forensics/SKILL.md
│   │   ├── memory-forensics/SKILL.md
│   │   ├── network-forensics/SKILL.md
│   │   ├── findings-validator/SKILL.md
│   │   └── ir-narrator/SKILL.md
│   └── hooks/
│       ├── pre-bash-broker-only.sh
│       ├── post-tool-obs.sh
│       └── stop-validate.sh
├── adws/
│   ├── investigate.py              # main outloop
│   ├── self_correct.py             # Phase G analyzer
│   └── best_of_n.py                # narrator judge
├── scripts/
│   ├── investigate.sh              # user-facing entrypoint
│   ├── inject-corruption.sh        # demo: truncate pcap, mis-state vol3 profile
│   └── export-execution-log.sh     # NDJSON for submission
├── evidence-samples/
│   ├── README.md                   # provenance + license
│   └── (downloaded SANS samples — gitignored, fetched by script)
├── docs/
│   ├── architecture.svg
│   ├── ACCURACY.md
│   ├── EVIDENCE.md
│   └── DEMO_SCRIPT.md
└── tests/
    ├── broker_smoke.sh
    ├── es_smoke.sh
    └── e2e_lonewolf.sh
```

## 4. Phased build (week-by-week)

### Phase 1 · Week 1 (May 6–12) — Substrate + Architectural Guardrail

**Goal:** A subagent can run `tsk_recover` via the broker, the result is hashed into Postgres, and `es cite F-001` returns a complete trace. Without this, nothing else matters.

- [ ] **1.1** Init Gitea repo, push scaffold, add Apache-2.0 LICENSE, draft README with placeholders.
- [ ] **1.2** `docker/postgres/Dockerfile` — base `postgres:17-bookworm`, build/install all 11 extensions, lock versions in build args. CI smoke: `docker run` + `psql -c "SELECT extname FROM pg_extension"` returns all 11.
- [ ] **1.3** `evidence-store/migrations/` — schema (see plan 03), idempotent.
- [ ] **1.4** `evidence-store/` Rust binary: subcommands `init`, `put-artifact`, `record-tool-call`, `record-finding`, `cite`, `merkle-root`, `search` (pgvector knn), `graph` (AGE Cypher passthrough). HTTP server on :8931 for hooks.
- [ ] **1.5** `broker/` Rust binary: subcommand `exec --tool <name> --args <json> --case <id>`. Loads tool spec from `broker/tools/*.toml`, validates args via pg_jsonschema, runs `podman run --rm --read-only --security-opt seccomp=seccomp/sleuth.json --memory 4g --pids-limit 256 ...`, streams stdout/stderr to evidence-store, returns `{tool_call_id, artifact_hash, exit_code, duration_ms}`.
- [ ] **1.6** Per-tool podman image Dockerfiles (only sleuthkit + volatility3 + tshark for Phase 1; rest in Phase 2).
- [ ] **1.7** Custom seccomp profile derived from `runc` default minus `ptrace`, `mount`, `pivot_root`, `unshare(CLONE_NEWUSER)`.
- [ ] **1.8** `.claude/settings.json` PreToolUse hook: allow only commands matching `^(./bin/sb|./bin/es|jq|grep|awk|sed|head|tail|cut|sort|uniq|wc|cat|column) `. Anything else exits 1 with explanation. **This is the architectural guardrail.**
- [ ] **1.9** PostToolUse hook: if tool was `./bin/sb exec`, parse stdout JSON and POST to `agent-obs:8910/event` with type `Sleuth.tool.executed`.
- [ ] **1.10** Smoke test `tests/broker_smoke.sh`: triage subagent runs `./bin/sb exec --tool fls --args '{"image":"/case/disk.E01","offset":0}'`, observes finding row, runs `./bin/es cite F-001`, asserts trace returns tool_call + blake3 + offset + exit_code.

**Phase 1 exit criteria:** smoke test green, hook blocks `bash -c "rm -rf /tmp/x"` and `curl evil.example.com`, Postgres has all extensions, obs receives events.

### Phase 2 · Week 2 (May 13–19) — Three Specialists

**Goal:** Each specialist subagent can independently complete an investigation in its evidence type and produce findings rows in Postgres. AGE graph populated. pgvector dedup working.

- [ ] **2.1** Skill `dfir-triage/SKILL.md` — input: case dir; output: `case_plan` row in DB with which specialists to spawn and tool budget per. Trigger: SHA, magic bytes, libmagic on every file in case dir; classify into disk/memory/pcap/log/mixed.
- [ ] **2.2** Skill + agent `disk-forensics`: tools allowed = `mmls`, `fls`, `icat`, `tsk_recover`, `tsk_loaddb`, `log2timeline.py`, `psort.py`, `yara`, `bulk_extractor`. Playbook: image hash → partition map → MFT timeline → carve → keyword/IOC sweep with yara rules from `~/.claude/skills/find-evil/disk-forensics/rules/`.
- [ ] **2.3** Skill + agent `memory-forensics`: tools = `vol3 banners`, `windows.info`, `windows.pslist`, `windows.pstree`, `windows.cmdline`, `windows.dlllist`, `windows.handles`, `windows.malfind`, `windows.netscan`, `windows.svcscan`, `windows.registry.printkey`. Playbook: profile → process tree → injected/hollowed → network → persistence → registry.
- [ ] **2.4** Skill + agent `network-forensics`: tools = `tshark`, `editcap`, `mergecap`, `zeek`, `suricata` (with ET-Open rules baked into image), `ngrep`. Playbook: pcap integrity (`capinfos`) → zeek logs → suricata alerts → tshark drilldown per IOC → DNS/HTTP/TLS extraction.
- [ ] **2.5** AGE schema migration: graph `g_case`, node labels `Process`, `File`, `RegistryKey`, `NetworkEndpoint`, `User`, `IOC`; edge labels `SPAWNED`, `WROTE`, `READ`, `LOADED`, `CONNECTED_TO`, `LOGGED_IN_AS`, `MATCHED`. Each finding insert also writes a Cypher MERGE.
- [ ] **2.6** pgvector embeddings: every finding's `claim` text and every artifact's preview hash gets a 1536-dim embedding (use `text-embedding-3-small` via OpenAI compatible Ollama running on g1-avilion or `claude --print` JSON output if budget tight). Dedup: cosine > 0.92 → mark `superseded_by`.
- [ ] **2.7** `parallel-agents` skill orchestrates fan-out: triage spawns specialists in parallel (Claude Code subagent multi-call).
- [ ] **2.8** Per-specialist smoke test using one curated mini-evidence (50MB disk, 200MB memory, 10MB pcap).

**Phase 2 exit criteria:** running each specialist solo produces ≥10 findings each with valid `tool_call_id`, AGE returns at least one path query (`MATCH (p:Process)-[:CONNECTED_TO]->(e:NetworkEndpoint) RETURN p,e`), pgvector dedup demonstrably collapses two repeat IOC findings to one.

### Phase 3 · Week 3 (May 20–26) — Validator + Narrator + Outloop

**Goal:** End-to-end investigation runs unattended from case directory to written report, with re-validation and self-correction.

- [ ] **3.1** Skill + agent `findings-validator`: takes `finding_id`, looks up tool_call, re-executes via broker (separate `validation_run` flag), compares output hash. Sets `findings.validation_status` ∈ {confirmed, refuted, inconclusive, drift}. Inconclusive triggers retry queue.
- [ ] **3.2** Skill + agent `ir-narrator`: queries confirmed findings + AGE attack-graph paths, emits structured Markdown report with `[F-NNN]` cites. Section template: Executive Summary → Initial Access → Execution → Persistence → Lateral Movement → Exfiltration → Indicators (MITRE ATT&CK aligned).
- [ ] **3.3** `adws/investigate.py` outloop:
    1. triage → write `case_plan`
    2. spawn specialists in parallel via `claude --print` subprocess
    3. wait for all → enqueue validator over each finding
    4. validator pass → if any inconclusive/refuted: trigger `self_correct.py`
    5. when validator queue empty for N minutes → spawn narrator
    6. best-of-N (3 candidates, Opus 4.7 judge) → write `report.md`, commit to branch `case/<id>`
- [ ] **3.4** `self_correct.py` (Phase G pattern): given a failed tool_call, builds structured retry prompt (last attempt args, exit_code, stderr tail, attempt history). Bounded to 3 retries per finding.
- [ ] **3.5** pg_cron jobs:
    - every 1h: enqueue validator over findings with `last_validated < now() - interval '1 hour'`
    - every 6h: vacuum + Merkle root rollup
    - every 15m: compact tool_calls hypertable
- [ ] **3.6** `agent-obs:8910` event types added: `Sleuth.case.started`, `Sleuth.specialist.{started,finished}`, `Sleuth.finding.created`, `Sleuth.validator.{confirmed,refuted,inconclusive}`, `Sleuth.self_correct.attempt`, `Sleuth.report.published`.
- [ ] **3.7** End-to-end smoke against the mini-evidence: `./scripts/investigate.sh ./tests/mini-case/` produces `report.md` with ≥3 confirmed findings, no refuted, ≤1 inconclusive.

**Phase 3 exit criteria:** unattended run from cold start to published report under 30 min on insa-server-2; report cites every claim; obs event timeline shows specialist parallelism and at least one validator pass.

### Phase 4 · Week 4 (May 27–Jun 2) — Real Sample Evidence + Self-Correction Demos

**Goal:** Pin the demo evidence, script and reproduce both self-corrections, tune until they fire reliably and visibly.

- [ ] **4.1** Choose canonical demo case: SANS LoneWolf (preferred — official SANS, public, matches "FIND EVIL" branding). Document provenance + license in `evidence-samples/README.md`. Fetch script in `scripts/fetch-evidence.sh` (no large files in git).
- [ ] **4.2** `scripts/inject-corruption.sh`:
    - **Tool crash injection:** writes `case/manifest.json` with `memory.os_profile = "Win10x64_19041"` deliberately wrong → vol3 windows.malfind exits non-zero with profile mismatch.
    - **Pcap truncation injection:** `dd if=case/network/lonewolf.pcap of=case/network/lonewolf.pcap bs=1 count=$(($(stat -c%s lonewolf.pcap) - 4096))` → tshark fails near EOF.
    - Both deterministic, both idempotent.
- [ ] **4.3** Memory specialist self-correction path: catches non-zero exit + stderr "no suitable address space" → emits `Sleuth.self_correct.attempt` → re-invokes `windows.info` → updates `case_plan.memory.os_profile` → re-invokes `windows.malfind` with correct profile → confirmed.
- [ ] **4.4** Network specialist self-correction path: catches tshark EOF error → invokes `editcap -E 0` recovery → `mergecap` → re-tshark on recovered slice → narrator marks affected findings `confidence=partial` (separate column from validation_status) — visibly demonstrates "confirmed vs inferred" distinction.
- [ ] **4.5** Run end-to-end three times unattended; demo passes if all three runs both self-correct and produce a report; tune retry prompts and tool stderr parsing until stable.
- [ ] **4.6** Capture event timeline of one good run for the architecture diagram annotations.

**Phase 4 exit criteria:** three consecutive clean runs against LoneWolf with both self-corrections visible in obs timeline and in the final report's "Self-Corrections" appendix.

### Phase 5 · Week 5 (Jun 3–9) — Submission Deliverables

**Goal:** Every Devpost requirement met, repo polish.

- [ ] **5.1** Architecture diagram via `excalidraw-diagram` skill → `docs/architecture.svg`. Show: hook → broker → podman → tools → evidence-store → Postgres + extensions → obs → ADW outloop. Annotate the architectural guardrail clearly.
- [ ] **5.2** `docs/EVIDENCE.md`: which dataset (LoneWolf), where to download, hash, what the agent found, mapped to ground truth from SANS solution.
- [ ] **5.3** `docs/ACCURACY.md`: false positives encountered + how surfaced, missed artifacts (vs SANS solution), hallucinations caught by validator with table `claim | tool_call_id | validation_status | reason`. **Honesty valued over perfection** — include 2–3 real misses.
- [ ] **5.4** `scripts/export-execution-log.sh`: dumps obs events + tool_calls hypertable + findings + validation_runs to `submission/execution-log.ndjson`. One file the judges can grep.
- [ ] **5.5** README rewrite — flow: what it is → judging criteria mapping → one-command install → run a demo → architecture diagram → links to plans/.
- [ ] **5.6** `scripts/investigate.sh` — single user-facing entrypoint: `./scripts/investigate.sh ./case-dir/ [--no-self-correct]`. Wraps compose up, ADW driver, report path output.
- [ ] **5.7** Demo video script in `docs/DEMO_SCRIPT.md`. Beats: 0:00–0:20 problem & approach → 0:20–0:50 architecture (one slide allowed for the diagram, then back to terminal) → 0:50–2:30 live run → 2:30–3:30 first self-correction (vol3) → 3:30–4:15 second self-correction (pcap, with confidence downgrade) → 4:15–4:50 `es cite` audit trail demo → 4:50–5:00 wrap. Total ≤5 min. Audio narration.
- [ ] **5.8** Record video with `kooha-recorder` skill (1080p60, mp4, mic on, desktop audio off). One full take, two backups.
- [ ] **5.9** Upload unlisted to YouTube; link in submission form.

**Phase 5 exit criteria:** every Devpost field has content, video uploaded, repo passes `./scripts/install-from-clean.sh` on a fresh VM.

### Phase 6 · Week 6 (Jun 10–14) — Buffer + Submit

- [ ] **6.1** Mirror Gitea → GitHub `wilaroca2021/find-evil-sleuth`. Verify Apache-2.0 detected in About.
- [ ] **6.2** Final dry run on a fresh Hetzner / DigitalOcean VM (8c/32g) — must complete from `git clone` to report in <45 min.
- [ ] **6.3** Submit on Devpost by Jun 13 23:59 EDT. Reserve Jun 14 for emergencies. Hard stop Jun 15 18:00 EDT.

## 5. Reuse map (do not rebuild)

| Existing | Used as |
|---|---|
| `agent-obs.service` :8910 (insa-server-2 `100.119.146.74`) | Submission's "Agent Execution Logs" requirement |
| Phase B PostToolUse validator (`tier_lock.py`) | Pattern reused in `findings-validator` agent |
| `adw` Rust CLI (`~/.local/bin/adw`) | Driver shell for `investigate.py` |
| `best_of_n.py`, `feature_adw.py`, `review_adw.py` in `tactical-agentic-coding/adws/` | Templates for narrator judge + outloop |
| `verification-before-completion` skill | Enforces no claim without `[F-NNN]` cite |
| `systematic-debugging` skill | Investigation reasoning template inside specialists |
| `parallel-agents` skill | Specialist fan-out |
| `desloppify` skill | Code quality pass on broker + es before submission |
| `port-registry` CLI | Reserve 5532 (pg), 8930 (broker http debug), 8931 (es http) |
| `excalidraw-diagram` skill | Architecture diagram |
| `kooha-recorder` skill | Video capture |
| `claude --print` subprocess pattern | All agent invocations from ADW |

## 6. Token & cost budget

- Sonnet 4.6 default for specialists, Opus 4.7 for validator + best-of-N judge.
- Estimated tokens per LoneWolf full run: ~600k input / ~80k output. Cost ≈ $4–6 (counting Opus passes). Budget for 50 full runs across the 5 weeks → ~$250 ceiling. Track via `obs` cost guardian (already exists from Safety Layer).
- Embedding for pgvector via local Ollama on g1-avilion → free, no API.

## 7. Cross-cutting risks (full register in plan 08)

| Risk | Mitigation |
|---|---|
| Postgres extension version conflicts (Timescale + AGE + cron) | Lock versions in Dockerfile build args; CI smoke runs on every merge |
| podman seccomp blocks legitimate forensics syscall | Profile derived from baseline run, allowlist drift; per-tool override file if needed |
| vol3 unreliable on arbitrary memory dumps | Stick to LoneWolf for demo; document supported profiles |
| Hub IP drift from `feedback_hub_ip_drift.md` | All addresses in `.env` only, never hardcoded |
| Demo flakiness on video day | Pre-script run, record three takes, keep second-best as backup |
| Devpost video YouTube limits | Upload 24h before deadline minimum (YT processing) |
| Rate-limit on insa-server-2 Anthropic account | Mirror runs on g1 (separate account) — proven pattern from `project_l5_zte_smoke.md` |
| Container escape via prompt injection in evidence | Architectural guardrail handles it; add fuzzy red-team test in Week 4 |

## 8. Component plans (siblings to this file)

- `01-postgres-substrate.md` — full schema, every extension's role, pg_cron jobs, AGE graph, pgvector usage, partman strategy
- `02-broker-design.md` — tool spec format, allowlist, podman invocation, seccomp profile, schema validation flow
- `03-evidence-store-design.md` — Merkle chain, BLAKE3 storage layout, `cite` semantics, search/graph endpoints
- `04-subagents-and-skills.md` — every agent's tools, system prompt, skill body, success/failure shape
- `05-adw-outloop.md` — investigate.py state machine, retry budget, parallelism caps, idempotency
- `06-self-correction-demos.md` — exact reproduction steps, expected obs events, video beats, fallback plans
- `07-submission-deliverables.md` — Devpost checklist, README structure, accuracy report template
- `08-risk-and-rollback.md` — full risk register with rollback plans, kill-switches, dry-run order

## 9. Definition of done (the hackathon ship list)

- [ ] Public Gitea repo with Apache-2.0 LICENSE detectable in About
- [ ] GitHub mirror at submission time
- [ ] README with one-command install and example run
- [ ] Architecture diagram SVG
- [ ] Evidence dataset documentation
- [ ] Accuracy report
- [ ] Agent execution logs export (NDJSON)
- [ ] ≤5 min YouTube video (terminal screencast + audio narration, both self-corrections visible)
- [ ] Devpost form completed
- [ ] At least one full LoneWolf run published as `case/lonewolf-2026-06-XX` branch with `report.md` + `submission/execution-log.ndjson`
