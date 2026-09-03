<div align="center">

# 🔍 SLEUTH

### Autonomous, tamper-evident DFIR on a Postgres substrate — from raw evidence to a cited report, with no human in the loop.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![CI](https://github.com/WilBtc/sleuth/actions/workflows/ci.yml/badge.svg)](https://github.com/WilBtc/sleuth/actions/workflows/ci.yml)
[![SANS FIND EVIL! Hackathon](https://img.shields.io/badge/SANS-FIND_EVIL!_2026-c8102e.svg)](https://www.sans.org/)
[![Built on SIFT](https://img.shields.io/badge/Built_on-SANS_SIFT-1a73e8.svg)](https://www.sans.org/tools/sift-workstation/)
[![Rust + Postgres 17](https://img.shields.io/badge/Rust_%2B_Postgres_17-000.svg)](#architecture)

**A Level-5 agentic DFIR system for the SANS "FIND EVIL!" hackathon.**
The constraint isn't a prompt — it's the architecture.

</div>

---

## ✅ Hackathon Submission Compliance

Every required turn-in item, mapped to its exact location so judges can verify completeness at a glance.

| # | Required item | Location |
|---|---------------|----------|
| 1 | Public code repository | **this repo** — https://github.com/WilBtc/sleuth |
| 2 | Open-source license (Apache-2.0) | [`LICENSE`](LICENSE) |
| 3 | README with setup instructions | this file → [Quick Start](#-quick-start) |
| 4 | Live deployment URL or step-by-step instructions | [Quick Start](#-quick-start) + [Persistent Inspector (SaaS)](#-persistent-inspector-saas) |
| 5 | Text description of features/functionality | [What it is](#what-it-is) + [`submission/devpost-form.md`](submission/devpost-form.md) |
| 6 | Demonstration video (≤5 min, audio narration, shows self-correction) | [`submission/demo.mp4`](submission/demo.mp4) · hosted URL in [`submission/devpost-form.md`](submission/devpost-form.md) |
| 7 | Architecture diagram | [`docs/architecture.svg`](docs/architecture.svg) (rendered in [Architecture](#architecture)) |
| 8 | Evidence dataset documentation | [`docs/EVIDENCE.md`](docs/EVIDENCE.md) |
| 9 | Accuracy report | [`docs/ACCURACY.md`](docs/ACCURACY.md) |
| 10 | Agent execution logs | [`submission/execution-log.ndjson`](submission/execution-log.ndjson) · live logs in [`logs/`](logs/) |

---

## What it is

**SLEUTH** runs a complete digital-forensics and incident-response investigation autonomously — from raw disk, memory, and network evidence to a structured, fully-cited report — with no human steps in the loop.

Three specialist subagents (disk, memory, network) drive the full SANS SIFT toolchain. Each produces `findings` rows in a Postgres 17 substrate, every one carrying a **BLAKE3-hashed artifact chain**, a **Merkle-chained audit trail**, and an **Apache AGE attack graph** node. A validator subagent re-executes *every* claim against the original evidence; an IR-narrator subagent turns confirmed findings into a report where every sentence carries a `[F-NNN]` citation back to its provenance.

### What makes it different

Most agentic DFIR tools keep the model in-bounds with prompt engineering. SLEUTH makes it **structurally impossible to misbehave**:

- 🔒 **The guardrail is an architecture, not an instruction.** A Bash `PreToolUse` hook exits 1 on any command that isn't `./bin/sb` (broker) or `./bin/es` (evidence-store) — enforced *before* the shell sees it. The agent literally cannot run `strings`, `grep`, or `tshark` directly.
- 🦀 **A Rust broker mediates every tool call.** It validates arguments with `pg_jsonschema`, runs each forensic binary in a **rootless podman container** with a custom **seccomp** profile and a **read-only** evidence mount, and streams stdout/stderr straight into Postgres.
- 🧠 **Hallucination is bounded by re-execution.** The validator re-runs each finding's original tool call with identical arguments and compares output. Anything that can't be reproduced is marked `refuted` and excluded from the report.
- 🗄️ **Postgres is the agent's brain.** Every tool invocation is a row. Every artifact is content-addressed. `./bin/es cite F-001` returns the complete provenance chain — tool call, arguments, exit code, stderr, BLAKE3 hash, artifact content — in under 100 ms. Judges can run live `SELECT` queries during the demo.

---

## 🏆 Judging Criteria → Design

| # | Criterion | How we address it |
|---|-----------|-------------------|
| 1 | **Autonomous Execution Quality** | ADW outloop + best-of-N narrator (Opus judge); per-finding event-driven re-validation (DB trigger + `LISTEN/NOTIFY`, no clock, no human input); self-correction bounded to 3 retries per finding |
| 2 | **IR Accuracy** | Validator re-runs every claim through the broker; `validation_status ∈ {confirmed, refuted, inconclusive, drift}`; pgvector cosine dedup collapses repeat IOCs. See [`docs/ACCURACY.md`](docs/ACCURACY.md) |
| 3 | **Breadth × Depth** | Three deep specialists on the full SIFT toolchain: Sleuth Kit + Plaso (disk), Volatility 3 (memory), tshark + Zeek + Suricata w/ ET-Open rules (network) |
| 4 | **Constraint Implementation** | Architectural guardrail: Bash hook + Rust broker + rootless podman + custom seccomp + read-only mount + `pg_jsonschema` — structural, not a system prompt |
| 5 | **Audit Trail** | BLAKE3 content-addressed artifacts, Merkle-chained `tool_calls` hypertable, `findings.tool_call_id` FK; `es cite F-NNN` returns full trace in <100 ms; pgaudit logs every `SELECT` |
| 6 | **Usability & Documentation** | One-command quickstart; persistent browser inspector; architecture SVG; `[F-NNN]` citations in every report paragraph |

---

## 🚀 Quick Start

```bash
# 1. Clone and start the Postgres substrate
git clone https://github.com/WilBtc/sleuth
cd sleuth
docker compose -f docker/compose.yaml up -d

# 2. Fetch a SANS evidence case (downloads from digitalcorpora.org)
./scripts/fetch-evidence.sh ./cases/lone-wolf/

# 3. Run the full investigation (triage → specialists → validator → narrator)
./scripts/investigate.sh ./cases/lone-wolf/

# 4. Cite any finding — full provenance chain in <100 ms
./bin/es cite F-001
```

`investigate.sh` drives the complete ADW pipeline: triage classifies the evidence, three specialists run in parallel, the validator re-executes every claim, and the narrator emits `report.md` into the case directory. Typical wall time on an 8-core / 32 GB machine: **20–40 minutes** for a full disk+memory+network case; the evidence download is the only long step.

A fast end-to-end smoke test (substrate already running) completes in seconds:

```bash
./scripts/smoke-test.sh --skip-compose   # clone-to-`cite` sanity check
```

---

## 🖥️ Persistent Inspector (SaaS)

`bin/sleuth-saas` is a compiled Rust web app — a persistent browser UI into any completed investigation. No Python, no notebook, no terminal required.

```bash
./scripts/saas.sh up      # starts Postgres if needed, launches inspector on :8932
```

Open **http://127.0.0.1:8932/** and navigate any case in under a second.

| Screen | URL | What you see |
|--------|-----|--------------|
| Case list | `/` | All cases with evidence counts and last-activity badge |
| Findings table | `/case/<id>/findings` | Every finding — confidence, validation_status, MITRE tag, drill-down |
| Finding detail | `/finding/<fid>` | Tool call, exact args, stdout hash, artifact content, Merkle root |
| Audit chain | `/case/<id>/audit` | Merkle-chained `tool_calls` with live verify badge (green = tamper-free) |
| Attack graph | `/case/<id>/graph` | Apache AGE nodes rendered with vis-network — lateral movement at a glance |

Screenshots: [`docs/saas-screenshots/`](docs/saas-screenshots/) · stop with `./scripts/saas.sh down`.

---

## 🧰 SIFT Integration

The hackathon is built around the **SANS SIFT Workstation**, and SLEUTH integrates the SIFT toolchain at two levels:

- **Per-tool sandboxed images** — each forensic binary (Sleuth Kit, Volatility 3, Plaso, tshark, Zeek, Suricata, YARA, bulk_extractor) runs in its own minimal rootless-podman image, registered in the broker's `tool_specs` table. This is the production path: tight sandboxing, fast startup, one container per tool call.
- **Full SIFT distribution** — `SLEUTH/sift-full` is the complete, **current** SANS SIFT Workstation (**2026-04-22**, Ubuntu 24.04, ~20 GB), extracted from the official SANS OVA via libguestfs (`virt-tar-out`) and imported as a container. Registered as the `mmls-sift-full` broker tool and reproducible via [`scripts/fetch-sift.sh`](scripts/fetch-sift.sh). Verified: Sleuth Kit 4.11.1, Volatility 3, Plaso/log2timeline 20260119. A maintained `digitalsleuth/sift-remnux` bundle is kept as the `sift-full:remnux-2024.10.19` fallback tag.

Every SIFT tool is reached **only** through the broker — validated, sandboxed, and recorded. No agent invokes a forensic binary directly.

---

## 🏗️ Architecture

![System Architecture](docs/architecture.svg)

The red dashed boundary marks the **architectural guardrail**: the `PreToolUse` hook blocks every command that does not match `./bin/sb` or `./bin/es`. The broker validates, sandboxes, and records. The evidence-store hashes, chains, and exposes. No agent touches the host shell directly.

```
ADW driver (adws/investigate.py)
    │
    ├── PreToolUse hook ──► blocks anything not ./bin/sb or ./bin/es
    │
    ├── ./bin/sb exec --tool <name> --args <json>
    │       │  validates args (pg_jsonschema)
    │       │  podman run --read-only --security-opt seccomp=sleuth.json
    │       └──► tool container (sleuthkit / vol3 / tshark / zeek / sift-full / …)
    │
    └── ./bin/es cite|record-finding|search|graph
            └──► Postgres 17
                  pgvector · AGE · TimescaleDB · pg_cron · pgaudit · …
```

The substrate is **Postgres 17** with eleven extensions: pgvector (semantic finding search), Apache AGE (attack graph), TimescaleDB (tool-call time series), pg_cron (scheduled validation sweeps), pg_partman, pg_trgm, pgcrypto, pg_stat_statements, pgaudit (tamper-evident query log), pg_jsonschema (argument validation), pg_graphql.

---

## 📐 Design Documents

Phase-by-phase design rationale lives in [`plans/`](plans/):

| File | Contents |
|------|----------|
| [`00-master-plan.md`](plans/00-master-plan.md) | Win condition, architecture overview, phased build schedule |
| [`01-postgres-substrate.md`](plans/01-postgres-substrate.md) | Full schema, each extension's role, pg_cron jobs, AGE graph, pgvector strategy |
| [`02-broker-design.md`](plans/02-broker-design.md) | Tool spec format, allowlist, podman invocation, seccomp profile |
| [`03-evidence-store-design.md`](plans/03-evidence-store-design.md) | Merkle chain, BLAKE3 layout, `cite` semantics, search/graph endpoints |
| [`04-subagents-and-skills.md`](plans/04-subagents-and-skills.md) | Each agent's tools, system prompt, skill body, success/failure shape |
| [`05-adw-outloop.md`](plans/05-adw-outloop.md) | investigate.py state machine, retry budget, parallelism caps, idempotency |
| [`06-self-correction-demos.md`](plans/06-self-correction-demos.md) | Exact reproduction steps for the self-correction demos |
| [`07-submission-deliverables.md`](plans/07-submission-deliverables.md) | Submission checklist, README structure, accuracy report template |
| [`08-risk-and-rollback.md`](plans/08-risk-and-rollback.md) | Full risk register with rollback plans and kill-switches |

---

## 📄 License

Apache-2.0 — see [`LICENSE`](LICENSE).

## 📚 Citations

**Evidence datasets:** SANS DFIR scenarios distributed via [digitalcorpora.org](https://digitalcorpora.org/) and the SANS hackathon dataset repository — see [`docs/EVIDENCE.md`](docs/EVIDENCE.md).

**Forensic toolchain:** The Sleuth Kit (Brian Carrier, Apache-2.0), Volatility 3 (Volatility Foundation, Apache-2.0), Zeek (Zeek Project, BSD), Suricata (OISF, GPL-2.0), tshark (Wireshark Foundation, GPL-2.0), Plaso (log2timeline project, Apache-2.0), SANS SIFT + REMnux distribution (digitalsleuth).

**Postgres extensions:** Apache AGE (Apache-2.0), pgvector (MIT), TimescaleDB (TSL/Apache-2.0), pg_cron (PostgreSQL License), pg_jsonschema (Apache-2.0), pgaudit (PostgreSQL License).
