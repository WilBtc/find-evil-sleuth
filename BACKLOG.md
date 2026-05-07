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

- [x] **2.1.4b Verify live Ollama embedding once g1 service is back**
  - Ollama on g1-avilion (`100.116.33.91:11434`) was unreachable 2026-05-06 — verify the worker's HTTP path against a real Ollama before P3 runs.
  - Done when: insert a finding on a dev-server with `EMBED_URL` set to a reachable Ollama; observe non-zero embedding within 10 s.
  - Touch: nothing (verification only) unless the embed call needs adjustment.

## P2.2 Skills + agents
- [x] **2.2.1 Skill `dfir-triage`**
  - Walks `/case`, classifies, writes `case_plan` rows.
  - Done when: `claude --print --agent triage --case <id>` populates `case_plan` for a synthetic 3-evidence case.
  - Touch: `.claude/skills/find-evil/dfir-triage/SKILL.md`, `.claude/agents/find-evil/triage.md`.

- [x] **2.2.2 Skill + agent `disk-forensics`**
  - Done when: solo run on phase15 mini-case produces ≥10 disk findings rows.
  - Touch: `.claude/skills/find-evil/disk-forensics/SKILL.md`, `.claude/agents/find-evil/disk-specialist.md`.

- [x] **2.2.3 Skill + agent `memory-forensics` (scaffold; real-evidence run deferred)**
  - **No real memory image is on dev-server yet** — `cases/synthetic-triage-001/memory.mem` is a 4-byte placeholder. Phase 4 will fetch SANS LoneWolf and retest. For now build the skill + agent files and exercise the broker contract using a stub fixture.
  - Done when: (a) `.claude/skills/find-evil/memory-forensics/SKILL.md` and `.claude/agents/find-evil/memory-specialist.md` exist with a vol3 playbook; (b) running the memory-specialist via `claude --print --append-system-prompt …` produces a syntactically valid `sb describe vol3` invocation and at least one *synthetic* finding row written via `es record-finding` against a fixture stdout file (script: `tests/fixtures/vol3-pslist-sample.txt` — claude must create this fixture from a real vol3 pslist man-page-style output if no sample is available); (c) BACKLOG ticked.
  - Touch: skill + agent + fixture file.

- [x] **2.2.4 Skill + agent `network-forensics` (scaffold; real-pcap run deferred)**
  - Same caveat: `cases/synthetic-triage-001/traffic.pcap` is a 4-byte placeholder. Phase 4 retests against LoneWolf pcap.
  - Done when: (a) skill + agent files; (b) generate a tiny valid pcap (≥3 packets, like `tests/phase1_5_smoke.sh` does for FAT16) under `tests/fixtures/`; (c) network-specialist run produces ≥10 network findings via real `tshark`/`zeek` against the tiny fixture.
  - Touch: skill + agent + tiny pcap fixture.

- [x] **2.2.5 Skill + agent `findings-validator`**
  - Re-executes claim's tool_call with `--validation`, sets `validation_status`.
  - Done when: validator marks 100% of step-2.2.2 findings as confirmed/refuted/inconclusive.

- [x] **2.2.6 Skill + agent `ir-narrator`**
  - Read-only, emits `report.md` with `[F-NNN]` cites per paragraph.
  - Done when: report passes the citation hook check.

## P2.3 Outloop
- [x] **2.3.1 ADW driver `adws/investigate.py`**
  - State machine (plan 05): TRIAGE → DISPATCH → SPECIALISTS → VALIDATING → NARRATING → DONE.
  - Done when: `./scripts/investigate.sh ./cases/mini/` emits a complete `report.md`.
  - Touch: `adws/investigate.py`, `scripts/investigate.sh`.

- [x] **2.3.2 Self-correction analyzer `adws/self_correct.py`**
  - Phase G structured retry prompt builder.
  - Done when: a deliberately-failed tool call triggers exactly 1 retry that succeeds.

- [x] **2.3.3 pg_cron re-validation**
  - Job: every 30 min enqueue `pending` and `>1h-old` findings.
  - Done when: `SELECT * FROM cron.job` shows the row.

## P3.1 Hardening — fix critical bugs from code review

- [x] **3.1.1 Lock down Bash hook allowlist (architectural-guardrail bypass)**
  - Remove `bash`, `sh`, `cargo`, `find`, `nohup`, `ssh`, `tee`, `podman` from `^(...)` regex in `.claude/hooks/pre-bash-broker-only.sh`. These were added during Phase 2 build to let ralph child do meta-work; specialists don't need them and they let `bash -c 'vol3 ...'` walk past the broker.
  - Keep: `./bin/sb`, `./bin/es`, `jq`, `grep`, `awk`, `sed`, `head`, `tail`, `cut`, `sort`, `uniq`, `wc`, `cat`, `column`, `date`, `test`, `[`, `echo`, `printf`, `pwd`, `ls`, `stat`, `file`, `xxd`, `psql`, `git status|diff|log`, `mkdir`, `touch`.
  - Done when: hook unit-test (a script that pipes 5 sample commands as JSON and asserts which exit 0/2) added under `tests/hook_allowlist.sh` and passes; specifically `bash -c 'id'`, `podman run alpine`, `cargo build`, `ssh somehost`, `nohup …` all return exit 2.
  - Touch: `.claude/hooks/pre-bash-broker-only.sh`, `tests/hook_allowlist.sh`.

- [x] **3.1.2 Add `stdout` and `stderr` aliases to broker JSON output**
  - Specialists/validator/narrator parse `.stdout` and `.stderr`; broker emits `.stdout_preview` and `.stderr_tail`. Add the bare names as additional keys (same content as the previews) so existing skill bodies work, AND keep the `_preview`/`_tail` keys for backwards compat.
  - Done when: `./bin/sb exec ... | jq -e '.stdout and .stderr and .stdout_preview and .stderr_tail'` returns true.
  - Touch: `broker/src/main.rs` (the `serde_json::json!` block in `exec`).

- [x] **3.1.3 Add `/scratch-case` writable mount + change output_* schemas to `^/scratch/`**
  - Tools that write (tsk_recover, bulk_extractor, editcap, log2timeline, psort, zeek) currently target `/case/...` but case dir is mounted ro. Add a second bind mount in `podman.rs::run` for a per-case writable dir (`/var/sleuth/scratch/<case>:/scratch:rw`) — keep `/case` ro to preserve evidence integrity.
  - Update all `output_dir`, `output_file`, `output` schema patterns in `migrations/002_tool_specs_seed.sql` from `^/case/` to `^/scratch/`.
  - Done when: `./bin/sb exec --case <id> --tool tsk_recover --args '{"image":"/case/disk.img","output_dir":"/scratch/recovered"}'` exits 0 and the recovered dir exists on host under `/var/sleuth/scratch/<id>/recovered/`.
  - Touch: `broker/src/podman.rs`, `migrations/006_output_paths_scratch.sql` (a new migration that ALTERs the seed rows; do not edit 002 in place).

- [x] **3.1.4 Fix specialist paths from `/case/<CASE_ID>/file` to `/case/file`**
  - Skills + agents for disk, memory, network all show example tool calls using `/case/<CASE_ID>/disk.img` etc. — but broker bind-mounts the case dir AS `/case`, so the correct path is `/case/disk.img` (no case_id segment). The network scaffold test uses the right path; everything else is wrong.
  - Audit all six skill bodies + six agent files; replace `/case/<CASE_ID>/` and `/case/${CASE_ID}/` with `/case/`.
  - Done when: `grep -rE '/case/<?CASE_ID' .claude/skills/find-evil .claude/agents/find-evil` returns nothing AND a smoke run of the disk specialist on the phase15 mini-case succeeds.
  - Touch: 6 skill files + 6 agent files.

- [x] **3.1.5 Drop the ≥10 findings quota; replace with "one finding per substantive observation"**
  - Skills currently say "produce ≥10 findings; if count<10, add more" which incentivizes fabrication. Network specialist explicitly records "no DNS traffic — confirmed clean" as findings. That undermines criterion 5 (audit trail).
  - Rewrite the "Done when" / step-N guidance in each specialist skill to: "Record a finding for each substantive observation supported by tool output. Do not pad. Empty/clean tool output is logged in obs but does NOT become a finding row." Same for the scaffold tests' "padding" rows — delete them.
  - Done when: scaffold tests still produce ≥3 findings per specialist (real ones), and grep for `confirmed clean|no evidence|no .* traffic.*confirmed` in skill bodies returns nothing.
  - Touch: 6 skill bodies + `tests/network_forensics_scaffold.sh` (lines 138/148/158/168) + `tests/memory_forensics_scaffold.sh` similar.

- [x] **3.1.6 Replace destructive pg_cron re-validation with append-only `validation_history`**
  - Current `005_pgcron_revalidation.sql` UPDATE-resets every confirmed finding back to `pending` every hour. That destroys the audit trail and makes the narrator's "WHERE validation_status='confirmed'" query empty mid-report.
  - Drop that migration. Add `migrations/007_validation_history.sql` with: `validation_history(history_id bigserial PK, finding_id text REFERENCES findings, status text, validated_at timestamptz default now(), validation_tool_call_id uuid)`. Update `evidence-store/src/findings.rs::set_validation` to INSERT into history AND update the latest status on `findings`. Update narrator to query latest history row when present.
  - pg_cron job rewritten to append a new row only when the latest history is >24h old AND status was previously `confirmed` (re-validation, not reset).
  - Done when: existing 11 confirmed disk findings still show `validation_status='confirmed'` after manual `SELECT cron.run_job(...)` invocation; new history rows are appended.
  - Touch: drop 005, add 007 migration, modify `evidence-store/src/findings.rs` `set_validation`.

## P3.2 Hardening — high-priority but non-blocking

- [x] **3.2.1 AGE Cypher injection fix in `sp_graph_assert` / `sp_graph_edge`**
  - Forensic strings (filenames `O'Reilly.docx`, registry paths, etc.) embedded in single-quoted Cypher will inject. Use `quote_literal()` for values; reject keys not matching `^[A-Za-z_][A-Za-z0-9_]*$`.
  - Done when: a regression test inserts a node with property value `bob's file.exe` and a query `MATCH (f:File {name:"bob's file.exe"})` returns it.
  - Touch: `migrations/003_age_helpers.sql` (rewrite functions; new migration `008_age_helpers_quoted.sql` that DROPs and re-creates).

- [x] **3.2.2 `findings.validation_tool_call_id` column for traceability**
  - `set_validation` accepts a tool_call_id but only flips `tool_calls.is_validation=true`. Add `findings.validation_tool_call_id uuid` column; bind it. Narrator's `es cite` should surface the validating tool call alongside the original.
  - Done when: `./bin/es cite F-007` includes both `tool_call.id` (original) and `validation_tool_call.id` for any confirmed finding.
  - Touch: `migrations/009_findings_validation_tool_call.sql`, `evidence-store/src/{findings.rs,cite.rs}`.

- [x] **3.2.3 Self-correct loop bounded retry of 3 (currently 1)**
  - `adws/self_correct.py::_attempt_loop` does ONE attempt; `investigate.py::state_self_correcting` calls it once. Restructure so up to 3 retries happen before bailing; each retry feeds prior failures into the next prompt.
  - Done when: a deliberately-broken tool call (mis-stated arg) triggers exactly 3 retry attempts visible in `self_corrections` table when none succeeds; one retry when first succeeds.
  - Touch: `adws/self_correct.py`, `adws/investigate.py`.

- [x] **3.2.4 Stop hook gates on agent identity (not transcript grep)**
  - `stop-cite-check.sh` greps the entire transcript JSON for "report.md" — fires for any conversation that mentions it. Read `.subagent_type` from the input JSON; only run check when subagent_type == 'narrator'. Use exit 2 (blocking) per Stop hook contract, not exit 1.
  - Done when: hook fires only for narrator stops; emits exit 2 with stderr reason if cite-coverage fails; emits exit 0 otherwise.
  - Touch: `.claude/hooks/stop-cite-check.sh`.

- [x] **3.2.5 Narrator uses read-only PG role**
  - Create `sleuth_ro` role with `SELECT` on cases, findings, tool_calls, validation_history, artifacts; no INSERT/UPDATE/DELETE. Narrator skill connects with `${PG_RO_URL}` instead of the read-write URL. Removes the "narrator could write to DB by accident" risk.
  - Done when: narrator subagent runs successfully on the phase15 case AND `INSERT INTO findings VALUES ...` from the narrator's connection raises permission denied.
  - Touch: `migrations/010_sleuth_ro_role.sql`, `.claude/skills/find-evil/ir-narrator/SKILL.md`, `.env.example`.

- [x] **3.2.6 Findings F-NNN allocation race fix (use a SEQUENCE)**
  - Concurrent specialists race on `MAX(...)+1` and lose to PK conflict. Replace with `CREATE SEQUENCE finding_seq`; format as `'F-' || lpad(nextval('finding_seq')::text, 3, '0')` in `findings.rs::record`.
  - Done when: 10 parallel `es record-finding` calls succeed without retry/conflict.
  - Touch: `migrations/011_finding_seq.sql`, `evidence-store/src/findings.rs`.

## P3.3 Real-evidence runs (depends on P3.1 done)

- [x] **3.3.1 Fetch SANS LoneWolf evidence dataset**
  - `scripts/fetch-evidence.sh lone-wolf` — downloads disk image (E01), memory dump (raw), pcap from SANS (or Magnet CTF). Writes to `evidence-samples/lone-wolf/` (gitignored). Records SHA256 in `evidence-samples/lone-wolf/MANIFEST`. Documents source in `docs/EVIDENCE.md`.
  - Done when: script exits 0, all three files present, SHA256 matches manifest, total size > 5GB.
  - Touch: `scripts/fetch-evidence.sh`, `docs/EVIDENCE.md`.

- [ ] **3.3.2 Disk specialist real-evidence run on LoneWolf**
  - Run `claude --print --append-system-prompt …` invoking the disk-specialist subagent against `evidence-samples/lone-wolf/`. Produces ≥30 real findings.
  - Done when: `SELECT count(*) FROM findings WHERE case_id LIKE 'lone-wolf-%' AND specialist='disk' AND validation_status='confirmed'` returns ≥20.
  - Touch: nothing (verifies existing specialist works on real evidence).

- [ ] **3.3.3 Memory specialist real-evidence run on LoneWolf**
  - Same shape, vol3 against the memory dump. ≥20 confirmed findings.
  - Touch: vol3 may need network=host on first run for symbol download; create `migrations/012_vol3_network_first_run.sql` to bump network='download-once' or similar IF needed.

- [ ] **3.3.4 Network specialist real-evidence run on LoneWolf**
  - tshark/zeek/suricata against the LoneWolf pcap. ≥20 confirmed network findings.

- [ ] **3.3.5 Full investigate.sh end-to-end on LoneWolf, narrator emits report**
  - `./scripts/investigate.sh evidence-samples/lone-wolf/` runs the full state machine. Produces `cases/lone-wolf-<ts>/report.md` with `[F-NNN]` cites for at least 60 confirmed findings.
  - Done when: report.md committed under a `case/lone-wolf-<date>` branch with execution log.

## P3.4 Self-correction demo prep (Phase 4 setup)

- [ ] **3.4.1 `scripts/inject-corruption.sh` for LoneWolf**
  - Per `plans/06-self-correction-demos.md`: truncate pcap by 4096 bytes; mis-state vol3 OS family hint in case manifest. Both deterministic, idempotent, reversible (script also has `--restore`).
  - Done when: running the script then executing investigate.sh produces both self-corrections visible in `self_corrections` table; restore brings evidence back to clean state.

- [ ] **3.4.2 Three consecutive clean investigate.sh runs against corrupted LoneWolf**
  - Each run completes, both self-corrections fire and recover, narrator marks affected findings `confidence=partial`. Build any retry-prompt tweaks needed for reliability.
  - Done when: three consecutive runs all pass; obs event timeline for each shows the same two self-correction events at predictable points.
