# find-evil-sleuth — Phase 2 backlog (ralph-driven)

> Each unchecked task is one autonomous ralph iteration. Iteration succeeds when the task's "Done when" condition is met. Ralph runs serially; tasks are ordered by dependency.
>
> **Kill switch:** `touch ~/.ralph-stop` (loop exits at the start of the next iteration).
> **Loop driver:** `adws/ralph.sh`
> **Per-iteration cap:** 30 min wall, $2 cost guardian.

## P2.1 Substrate prep
- [x] **2.1.1 Register all 9 forensics tools in `tool_specs`**
  - Add: mmls, fls, icat, tsk_recover, log2timeline, plaso/psort, vol3, tshark, editcap, zeek (via image), suricata (via image), yara, bulk_extractor.
  - Done when: `./bin/sb list-tools` prints ≥9 rows AND `./bin/sb describe vol3` returns the spec.
  - Touch: `migrations/002_tool_specs_seed.sql`, push, run on dev-server.

- [x] **2.1.2 Build remaining per-tool podman images on dev-server**
  - Built: sleuthkit, volatility3, tshark, yara, suricata (+ET-Open), zeek (+ET-Open).
  - Plaso deferred to 2.1.2b (pip-from-source against ~30 forensic-library Python bindings fails on slim base — needs `log2timeline/plaso` upstream image).
  - Done when: `podman image ls find-evil-sleuth/*` lists ≥6.

- [x] **2.1.2b Plaso podman image (use upstream log2timeline/plaso base)**
  - Switch `broker/tools/plaso.Dockerfile` to `FROM log2timeline/plaso:latest` (or pinned tag) — do NOT pip install plaso from source. Bake `log2timeline.py` + `psort.py` entrypoints. Keep nobody:nogroup user, /scratch tmpfs.
  - Done when: `podman image ls find-evil-sleuth/plaso` shows the image AND `podman run --rm find-evil-sleuth/plaso log2timeline.py --version` returns the plaso version line.
  - Touch: `broker/tools/plaso.Dockerfile`.

- [x] **2.1.3 AGE graph schema + helpers**
  - Cypher MERGE templates per node/edge type; SQL function `sp_graph_assert(label, props_json)`.
  - Done when: `psql -c "SELECT * FROM cypher('case_graph', $$MATCH (n) RETURN count(n)$$) AS (n agtype)"` works.
  - Touch: `migrations/003_age_helpers.sql`.

- [x] **2.1.4 pgvector embedding worker (skeleton)**
  - `es worker --embeddings` listens on NOTIFY/LISTEN, calls Ollama nomic-embed-text on g1, writes 1536-dim.
  - Done when: insert a finding, see embedding column populated within 10s.
  - Touch: `evidence-store/src/worker.rs`, `evidence-store/src/main.rs` (add Worker subcommand).

- [~] **2.1.4b Verify live Ollama embedding once g1 service is back** *(deferred — ralph skips `[~]`)*
  - Ollama on g1-avilion (`100.116.33.91:11434`) was unreachable 2026-05-06 — verify the worker's HTTP path against a real Ollama before P3 runs.
  - Done when: insert a finding on a dev-server with `EMBED_URL` set to a reachable Ollama; observe non-zero embedding within 10 s.
  - Touch: nothing (verification only) unless the embed call needs adjustment.

## P2.2 Skills + agents
- [x] **2.2.1 Skill `dfir-triage`**
  - Walks `/case`, classifies, writes `case_plan` rows.
  - Done when: `claude --print --agent triage --case <id>` populates `case_plan` for a synthetic 3-evidence case.
  - Touch: `.claude/skills/find-evil/dfir-triage/SKILL.md`, `.claude/agents/find-evil/triage.md`.

- [ ] **2.2.2 Skill + agent `disk-forensics`**
  - Done when: solo run on phase15 mini-case produces ≥10 disk findings rows.
  - Touch: `.claude/skills/find-evil/disk-forensics/SKILL.md`, `.claude/agents/find-evil/disk-specialist.md`.

- [ ] **2.2.3 Skill + agent `memory-forensics`**
  - Done when: solo run on a sample memory image produces ≥10 memory findings rows.
  - Touch: corresponding skill + agent files.

- [ ] **2.2.4 Skill + agent `network-forensics`**
  - Done when: solo run on a sample pcap produces ≥10 network findings rows.

- [ ] **2.2.5 Skill + agent `findings-validator`**
  - Re-executes claim's tool_call with `--validation`, sets `validation_status`.
  - Done when: validator marks 100% of step-2.2.2 findings as confirmed/refuted/inconclusive.

- [ ] **2.2.6 Skill + agent `ir-narrator`**
  - Read-only, emits `report.md` with `[F-NNN]` cites per paragraph.
  - Done when: report passes the citation hook check.

## P2.3 Outloop
- [ ] **2.3.1 ADW driver `adws/investigate.py`**
  - State machine (plan 05): TRIAGE → DISPATCH → SPECIALISTS → VALIDATING → NARRATING → DONE.
  - Done when: `./scripts/investigate.sh ./cases/mini/` emits a complete `report.md`.
  - Touch: `adws/investigate.py`, `scripts/investigate.sh`.

- [ ] **2.3.2 Self-correction analyzer `adws/self_correct.py`**
  - Phase G structured retry prompt builder.
  - Done when: a deliberately-failed tool call triggers exactly 1 retry that succeeds.

- [ ] **2.3.3 pg_cron re-validation**
  - Job: every 30 min enqueue `pending` and `>1h-old` findings.
  - Done when: `SELECT * FROM cron.job` shows the row.
