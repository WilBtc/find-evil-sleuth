# Devpost Submission Form — find-evil-sleuth

> Draft content for every field on the Devpost submission page.
> Replace placeholder URLs once 4.3.1 (GitHub mirror) and 4.2.3 (YouTube upload) are complete.

---

## Project Name

find-evil-sleuth

---

## Tagline

Architecturally-sandboxed agentic DFIR for SIFT — Postgres is the agent's brain.

---

## Description

### What it is

find-evil-sleuth is a Level-5 agentic digital-forensics and incident-response (DFIR) system built for the SANS "FIND EVIL!" hackathon. Three specialist subagents — disk, memory, and network — run the complete SIFT toolchain autonomously. Each specialist produces `findings` rows in a Postgres 17 substrate that carry a BLAKE3-hashed artifact chain, a Merkle-chained audit trail, and an Apache AGE attack graph. A validator subagent re-executes every single claim against original evidence; an IR-narrator subagent turns confirmed findings into a structured report with `[F-NNN]` citations. From raw evidence to a cited, provenance-complete report, with zero human steps in the loop.

### How we built it

The architectural guardrail is not a system prompt — it is a Bash `PreToolUse` hook that exits 1 on any command that is not `./bin/sb` (sleuth-broker) or `./bin/es` (evidence-store), enforced at the Claude Code hook layer before the shell ever sees the command. The Rust broker behind `./bin/sb` validates every tool argument via `pg_jsonschema`, runs each forensic binary (sleuthkit, Volatility 3, tshark, Zeek) inside a rootless podman container with a custom seccomp profile and a read-only evidence mount, and streams stdout/stderr directly into Postgres. No agent can escape to raw shell, the host network, or the host filesystem — the constraint is structural, not instructional. The substrate is Postgres 17 with eleven extensions: pgvector for semantic search over findings, Apache AGE for the attack graph, TimescaleDB for time-series tool calls, pg_cron for scheduled validation sweeps, pg_jsonschema for argument validation, and pgaudit for a tamper-evident query log. Every tool invocation is a row. Every artifact is content-addressed. `./bin/es cite F-001` returns the complete provenance chain in under 100 ms.

### What makes it different

Most agentic DFIR systems rely on prompt engineering to keep the agent in bounds. find-evil-sleuth treats the constraint as an engineering problem: the agent literally cannot run `strings`, `grep`, or `tshark` except through the broker, which enforces a JSON schema, applies a seccomp profile, and records every byte of output before the agent sees it. Hallucination is structurally bounded — the validator subagent re-runs the original tool call with identical arguments and compares output; any finding that cannot be reproduced is marked `refuted` and excluded from the report. The result is an audit trail that a judge (or an incident commander) can interrogate with live SQL during the demo: `SELECT * FROM findings WHERE validation_status = 'confirmed'` returns ground truth, not a language model's memory of ground truth.

---

## Demo Video

<!-- Replace with YouTube unlisted URL after 4.2.3 is complete -->
**URL:** `https://youtu.be/PLACEHOLDER_REPLACE_AFTER_UPLOAD`

- Duration: ≤5 minutes
- Format: terminal screencast with audio narration
- Shows: real LoneWolf evidence, full ADW pipeline, ≥2 self-correction sequences, live `es cite` provenance lookup

---

## Code Repository

<!-- Replace with GitHub public mirror URL after 4.3.1 is complete -->
**URL:** `https://github.com/wilaroca2021/find-evil-sleuth`

- License: Apache-2.0
- Branch: `main`

---

## Built With

- Claude Code (claude-sonnet-4)
- Rust (sleuth-broker binary, pg_jsonschema arg validation)
- Python (ADW driver, specialist subagent prompts)
- PostgreSQL 17
  - pgvector (semantic search)
  - Apache AGE (attack graph)
  - TimescaleDB (tool_calls hypertable)
  - pg_cron (scheduled validation)
  - pg_partman (partition management)
  - pg_trgm (trigram search)
  - pgcrypto (BLAKE3 hashing via extensions)
  - pg_stat_statements (query profiling)
  - pgaudit (tamper-evident audit log)
  - pg_jsonschema (tool argument validation)
  - pg_graphql (GraphQL API over findings)
- podman (rootless containers + seccomp profiles)
- sleuthkit / TSK (disk forensics — mmls, fls, icat, tsk_recover)
- Volatility 3 (memory forensics — pslist, malfind, netscan, cmdline)
- Zeek (network protocol analysis)
- tshark / Wireshark (packet capture analysis)
- Suricata (network IDS signatures)
- bulk_extractor (artifact carving)
- YARA (malware pattern matching)
- plaso / log2timeline (super-timeline generation)
- Docker Compose (substrate orchestration)
- SANS SIFT Workstation (base forensics environment)

---

## Try It Out

**Quickstart:**

```bash
git clone https://github.com/wilaroca2021/find-evil-sleuth
cd find-evil-sleuth
docker compose -f docker/compose.yaml up -d
./scripts/fetch-evidence.sh ./cases/lone-wolf/
./scripts/investigate.sh ./cases/lone-wolf/
./bin/es cite F-001
```

Full instructions: [README.md](../README.md)

Estimated wall time on an 8-core / 32 GB VM: 20–40 minutes for the complete SANS LoneWolf dataset.

---

## Additional Links

- Architecture diagram: [`docs/architecture.svg`](../docs/architecture.svg)
- Evidence documentation: [`docs/EVIDENCE.md`](../docs/EVIDENCE.md)
- Accuracy report (honest self-assessment): [`docs/ACCURACY.md`](../docs/ACCURACY.md)
- Demo script: [`docs/DEMO_SCRIPT.md`](../docs/DEMO_SCRIPT.md)
- Execution log (full audit trail): [`submission/execution-log.ndjson`](./execution-log.ndjson)

---

*Generated by ralph autonomous loop — task 4.3.2*
