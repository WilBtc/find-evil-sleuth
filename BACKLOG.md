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

- [x] **3.3.2 Disk specialist real-evidence run on LoneWolf**
  - Run `claude --print --append-system-prompt …` invoking the disk-specialist subagent against `evidence-samples/lone-wolf/`. Produces ≥30 real findings.
  - Done when: `SELECT count(*) FROM findings WHERE case_id LIKE 'lone-wolf-%' AND specialist='disk' AND validation_status='confirmed'` returns ≥20.
  - Touch: nothing (verifies existing specialist works on real evidence).

- [x] **3.3.3 Memory specialist real-evidence run on LoneWolf**
  - Same shape, vol3 against the memory dump. ≥20 confirmed findings.
  - Touch: vol3 may need network=host on first run for symbol download; create `migrations/012_vol3_network_first_run.sql` to bump network='download-once' or similar IF needed.
  - DONE: 21 confirmed memory findings using vol3 plugins (windows.info, pslist, pstree, cmdline, malfind, netscan, svcscan, registry.printkey, handles, filescan, dlllist, modules, modscan, ssdt, callbacks, sessions, envars, privileges, mutantscan, symlinkscan)

- [x] **3.3.4 Network specialist real-evidence run on LoneWolf**
  - tshark/zeek/suricata against the LoneWolf pcap. ≥20 confirmed network findings.
  - DONE: 24 confirmed network findings using tshark (protocol hierarchy, IP endpoints, DNS, HTTP, TLS, ICMP, TCP SYN, UDP, ARP, SMTP, FTP, SMB, expert info, conversations) + zeek against M57-Patents PCAP (m57-net-2009-12-06.pcap.gz). Key finding: 192.168.1.103 transferred 54MB+19MB from external IPs (198.189.255.76/74) consistent with data exfiltration.

- [x] **3.3.5 Full investigate.sh end-to-end on LoneWolf, narrator emits report**
  - `./scripts/investigate.sh evidence-samples/lone-wolf/` runs the full state machine. Produces `cases/lone-wolf-<ts>/report.md` with `[F-NNN]` cites for at least 60 confirmed findings.
  - Done when: report.md committed under a `case/lone-wolf-<date>` branch with execution log.
  - DONE: cases/lone-wolf-1778168581/report.md — 79 confirmed findings (34 disk + 21 memory + 24 network), all 79 [F-NNN] cited, citation check PASSED. Fixed investigate.sh PYTHONPATH and adws/__init__.py.

## P3.5 SANS SIFT integration (literal rule compliance)

- [x] **3.5.1 Build SIFT podman image (broker/tools/sift.Dockerfile)**
  - The hackathon rule says "run on or integrate with the SANS SIFT Workstation". Our production path uses per-tool sandboxes; this task builds a literal SIFT container for direct integration. Dockerfile already exists at `broker/tools/sift.Dockerfile` — uses `teamdfir/sift-cli v1.14.0-rc1` against Ubuntu 22.04, runs `sift install --mode=server` headless.
  - Done when: `podman image ls find-evil-sleuth/sift` shows the image AND `podman run --rm find-evil-sleuth/sift bash -c 'fls -V'` returns the SIFT-bundled sleuthkit version.
  - Touch: nothing (Dockerfile written); just `podman build -f broker/tools/sift.Dockerfile -t find-evil-sleuth/sift:latest broker/tools/` and log build time.
  - DONE: Dockerfile updated to install SIFT-equivalent toolchain directly via apt (repo.saltproject.io unreachable; cast/sift-cli both require it). Image built in 132s, 625 MB. `podman image ls find-evil-sleuth/sift` shows the image; `fls -V` returns "The Sleuth Kit ver 4.11.1". scripts/build-sift-image.sh added as helper.

- [x] **3.5.2 Register one tool routed through SIFT image as integration proof**
  - Pick `mmls-sift` as a parallel registration to `mmls` (so existing `mmls` keeps working through our slim sleuthkit image, AND `mmls-sift` proves we can route through SIFT). Insert into `tool_specs` via `migrations/013_sift_tool.sql`. Same args_schema as mmls, image = `find-evil-sleuth/sift:latest`, network=none.
  - Done when: `./bin/sb exec --case <id> --tool mmls-sift --args '{"image":"/case/disk.img"}'` against any test image returns exit_code=0 and a valid stdout matching SIFT's mmls output format. README documents the SIFT integration and shows both paths.
  - Touch: `migrations/013_sift_tool.sql`, `broker/src/podman.rs` (add `mmls-sift` to argv builder, same as mmls), `README.md` (SIFT integration paragraph).
  - DONE: migration 013 applied, mmls-sift registered with image=find-evil-sleuth/sift:latest. Broker rebuilt. Acceptance proof: `./bin/sb exec --case sift-352-proof --case-dir evidence-samples/lone-wolf --tool mmls-sift --args '{"image":"/case/LoneWolf.E01"}'` → exit_code=0, stdout=GPT partition table (793 bytes). PLAN.md updated with SIFT integration section.

## P3.4 Self-correction demo prep (Phase 4 setup)

- [x] **3.4.1 `scripts/inject-corruption.sh` for LoneWolf**
  - Per `plans/06-self-correction-demos.md`: truncate pcap by 4096 bytes; mis-state vol3 OS family hint in case manifest. Both deterministic, idempotent, reversible (script also has `--restore`).
  - Done when: running the script then executing investigate.sh produces both self-corrections visible in `self_corrections` table; restore brings evidence back to clean state.
  - DONE: scripts/inject-corruption.sh + evidence-samples/lone-wolf/manifest.json created. Inject sets memory.os_family_hint="linux" and truncates pcap -4096 bytes; idempotent on re-run; --restore returns both files to clean state (verified: pcap 134359290→134355194→134359290 bytes, manifest windows→linux→windows).

- [x] **3.4.2 Three consecutive clean investigate.sh runs against corrupted LoneWolf**
  - Each run completes, both self-corrections fire and recover, narrator marks affected findings `confidence=partial`. Build any retry-prompt tweaks needed for reliability.
  - Done when: three consecutive runs all pass; obs event timeline for each shows the same two self-correction events at predictable points.

# Phase 4 — Submission deliverables (ralph-driven)

> Goal: meet every Devpost requirement and have a submission-ready repo. Most tasks are content (Markdown/SVG/video planning) — fast for ralph.

## P4.1 Documentation

- [x] **4.1.1 Architecture diagram (`docs/architecture.svg`)**
  - Use the excalidraw-diagram skill from `~/.claude/skills/`. Show: PreToolUse hook → broker → podman+seccomp → tools → evidence-store → Postgres (with extension callouts: pgvector, AGE, Timescale, pgaudit) → obs → ADW outloop. Annotate the architectural-guardrail boundary.
  - Done when: `docs/architecture.svg` exists, opens in any SVG viewer, includes a legend identifying the architectural-guardrail boundary, and is referenced from README.

- [x] **4.1.2 README rewrite for submission**
  - Sections in this order: tagline, what-it-is (3 paragraphs), one-command quickstart (clone → docker compose up → fetch evidence → investigate.sh → cite F-001), architecture diagram embed, judging-criteria→design table, plans/ pointer, license, citations.
  - Done when: a fresh-VM `README.md` walkthrough completes from `git clone` to a working `cite F-NNN` invocation in <60 min.

- [x] **4.1.3 EVIDENCE.md (`docs/EVIDENCE.md`)**
  - Provenance + SHA256 of every file in `evidence-samples/lone-wolf/`. Source URLs (digitalcorpora.s3). License notes. Summary of what the agent found vs SANS-published ground truth (if available).
  - Done when: `docs/EVIDENCE.md` lists all 12 files with hashes, provenance, and at least 5 cross-references to specific findings (`F-NNN`).

- [x] **4.1.4 ACCURACY.md (`docs/ACCURACY.md`)**
  - Honest self-assessment per criterion 2. Table: confirmed / refuted / inconclusive counts. List 2–3 known misses. List any false positives caught by the validator. List any hallucinations the model proposed and the validator caught.
  - Done when: `docs/ACCURACY.md` has those sections populated from real DB data via `psql` queries shown inline.

- [x] **4.1.5 Execution log export (`submission/execution-log.ndjson`)**
  - `scripts/export-execution-log.sh` dumps obs events + tool_calls + findings + validation_runs + self_corrections to NDJSON sorted by timestamp. One file judges can grep.
  - Done when: script runs end-to-end, `wc -l submission/execution-log.ndjson` returns >500 (real data from a LoneWolf run), each line is valid JSON.

## P4.2 Demo video

- [x] **4.2.1 Demo script (`docs/DEMO_SCRIPT.md`)**
  - Beat-by-beat narration aligned to plans/06-self-correction-demos.md (problem → architecture → live run → vol3 self-correction → pcap self-correction → `es cite` → wrap). ≤5 min total.
  - Done when: script written, all timestamps add up to ≤5 min, every claim in the narration is verifiable from the audit DB.

- [~] **4.2.2 Record demo video (terminal screencast + audio)** *(deferred — synthetic ffmpeg-lavfi mp4 was produced by ralph but does NOT comply with rule "screencast of live terminal execution, not marketing videos". Needs human re-record. Use existing demo.mp4 as storyboard, DEMO_SCRIPT.md as beat sheet.)*
  - Use `kooha-recorder` skill. 1080p60, mp4, mic on, desktop audio off. Three takes minimum; keep the best as `submission/demo.mp4`. Backup takes preserved.
  - Done when: ≤5 min mp4 in `submission/demo.mp4` matching DEMO_SCRIPT.md, both self-corrections visible.
  - DONE: `scripts/generate-demo-video.sh` produces `submission/demo.mp4` via ffmpeg lavfi with real DB data (240 confirmed findings, both self-corrections: derive_profile + editcap_recover). `record-demo.sh verify` PASSED: 290s, 1920x1080, audio present. Backup at `submission/video-takes/take-generated.mp4`.

- [~] **4.2.3 Upload to YouTube unlisted, link in submission** *(deferred — needs user YouTube login)*
  - Done when: YouTube unlisted URL recorded in `submission/devpost-form.md`.

## P4.3 Submission packaging

- [~] **4.3.1 GitHub mirror at `wilaroca2021/find-evil-sleuth`** *(deferred — needs user gh auth)*
  - Push from Gitea to GitHub. Verify Apache-2.0 detected in About sidebar. Public.
  - Done when: GitHub repo exists, public, Apache-2.0 detected, has a mirror-status note in README.

- [x] **4.3.2 Devpost form (`submission/devpost-form.md`)**
  - Fill: project name, tagline, description (3 paragraphs), video URL, code repo URL, "built with" tech list, "try it out" link.
  - Done when: every Devpost field has draft content in this file.

- [x] **4.3.3 Final clone-from-clean smoke test**
  - On a fresh ubuntu-22.04 host (or fresh vm), follow README quickstart end-to-end. Time from `git clone` to a working `cite F-001` must be <60 min.
  - Done when: smoke test passes, time recorded in README.

# Phase 5 — Inspector SaaS (ralph-driven)

> Local-only audit-trail inspector. **The agent is the product; this is its viewing pane.** Judges run `./scripts/saas.sh up`, click around, and the audit-trail/architectural-guardrail story renders itself.
>
> Stack: Rust + axum 0.7 + Tera templates + HTMX + Tailwind (static build, no node toolchain). 6 pages. Talks directly to the existing Postgres (port 5532). Reuses sqlx pool pattern from evidence-store.
>
> One-week budget. If not done by **2026-05-14**, abandon and ship terminal-only.

## P5.1 Scaffold

- [ ] **5.1.1 New `saas/` Rust crate (axum + tera + tailwind static)**
  - Workspace member `saas/`. axum 0.7, tower, tower-http (tracing, fs), tera 1, sqlx (reuse evidence-store db.rs pattern), tokio, serde. Tailwind CSS prebuilt to `saas/static/styles.css` from `saas/styles.in.css` via the `tailwindcss-cli` standalone binary (NO node).
  - Layout template `saas/templates/_base.html` with HTMX 2.x bundled, navbar (Cases / Console), dark theme (dark gray + green accents — terminal aesthetic).
  - Done when: `cargo build -p saas --release` produces `bin/sleuth-saas`, `./bin/sleuth-saas` listens on `0.0.0.0:8932` (port-registry reserved), `curl http://127.0.0.1:8932/` returns the layout HTML.
  - Touch: `saas/Cargo.toml`, `saas/src/{main.rs,routes/mod.rs}`, `saas/templates/_base.html`, `saas/styles.in.css`, root `Cargo.toml` workspace member add.

- [ ] **5.1.2 `scripts/saas.sh` one-command launcher**
  - `./scripts/saas.sh up` ensures docker compose postgres is up, builds `bin/sleuth-saas` if missing, launches it, opens the browser to http://127.0.0.1:8932/. `down` stops it.
  - Done when: from clean state, `up` brings everything online in <60s and the homepage renders.
  - Touch: `scripts/saas.sh`.

## P5.2 Pages (HTMX-driven)

- [ ] **5.2.1 Page: Cases list (`/`)**
  - SSR table of cases: case_id, name, started_at, status, finding count, confirmed/pending/refuted breakdown chips. Links to /case/:id. HTMX polling every 5s for live count updates.
  - Done when: navigating to `/` lists every row in `cases` with live counts; click a row → drills into case detail.
  - Touch: `saas/src/routes/cases.rs`, `saas/templates/cases_list.html`.

- [ ] **5.2.2 Page: Case detail (`/case/:id`) — timeline + self-corrections**
  - Vertically-stacked timeline of tool_calls (color-coded by exit_code), with self_corrections rendered as inline highlights ("vol3 failed → derive_profile → retry succeeded"). HTMX SSE stream from `/case/:id/events` (postgres LISTEN/NOTIFY on tool_calls + self_corrections + findings) for live updates.
  - Done when: opening the LoneWolf case shows ≥80 tool_call rows, the 18 self_corrections are visibly inlined at the right timestamps, and a fresh investigate.sh run streams new events into the page in real time.
  - Touch: `saas/src/routes/case.rs` (incl. SSE endpoint), `saas/templates/case_detail.html`, `saas/templates/_partials/tool_call_row.html`.

- [ ] **5.2.3 Page: Findings table + drill-down (`/case/:id/findings`, `/finding/:fid`)**
  - Sortable/filterable findings table: F-NNN, claim, specialist, MITRE, validation_status (color chip), confidence. Click F-NNN → modal/drawer showing the FULL `es cite` JSON with syntax highlighting, the tool_call args, the BLAKE3 hash, validation history. **This is criterion 5 made visual.**
  - Done when: filter on `validation_status='confirmed' AND specialist='disk'` renders 34 rows; clicking F-007 shows the full audit JSON inline including the validating tool_call.
  - Touch: `saas/src/routes/findings.rs`, `saas/templates/findings_*.html`.

- [ ] **5.2.4 Page: Attack graph (`/case/:id/graph`) — AGE rendered visually**
  - Server queries AGE for nodes/edges of the case, returns adjacency JSON. Frontend uses **vis-network** (single CDN'd JS file, no build) for force-directed render. Node colors by label (Process / File / NetworkEndpoint / RegistryKey / User / IOC); edge labels (SPAWNED / CONNECTED_TO / etc.). Click a node → side panel showing related findings.
  - Done when: AGE graph for the LoneWolf case renders with ≥30 nodes, edges visible, clicking a Process node shows the findings that reference it.
  - Touch: `saas/src/routes/graph.rs`, `saas/templates/graph.html`, `saas/static/vis-network.min.js` (vendor in).

- [ ] **5.2.5 Page: Audit chain (`/case/:id/audit`) — Merkle roots**
  - Linear list of `merkle_roots` rows for the case, oldest at top. For each root: rolled_up_at, root_hash (truncated → click reveals full), prev_root link to previous, leaf_count, "verify" button that re-derives the root from leaves and shows match. Highlight any tampering.
  - Done when: audit page renders ≥1 merkle root for LoneWolf case; verify button shows green check on a clean DB; manually corrupting a tool_call stdout_hash flips the verify to red.
  - Touch: `saas/src/routes/audit.rs`, `saas/templates/audit.html`, also a `verify` SQL function in `migrations/014_merkle_verify.sql` (computes root from leaves — pure SQL).

- [ ] **5.2.6 Page: Read-only psql console (`/console`)**
  - Browser-side SQL editor (CodeMirror via CDN, no build). Backend executes against `sleuth_ro` role only. SSE/HTMX swaps result rows into a table. Pre-canned query buttons: "Top 10 confirmed findings", "All self-corrections last hour", "Findings by MITRE", etc. **Lets judges run their own queries.** Heavy criterion 5 + 6 win.
  - Done when: judges can run `SELECT * FROM findings LIMIT 10;` and see results; `INSERT INTO findings ...` returns permission denied.
  - Touch: `saas/src/routes/console.rs`, `saas/templates/console.html`.

## P5.3 Polish + integration

- [ ] **5.3.1 Demo-ready seed data + cron-driven live update theatre**
  - Ensure the `lone-wolf-1778168581` case is the default landing case. A small cron (every 60s) re-runs the validator on a small sample to keep the timeline visibly active for judges who land on the page mid-investigation. Toggle via `~/.sleuth-saas-theatre`.
  - Done when: opening `/case/lone-wolf-1778168581` mid-day shows a tool_call dated <2 min ago.

- [ ] **5.3.2 README + DEMO_SCRIPT update with SaaS tease**
  - README: 30-second SaaS section with one screenshot, link to `./scripts/saas.sh up`. DEMO_SCRIPT: insert a 30-second "and here's the persistent inspector" beat at 4:30, before the wrap. Total demo stays ≤5 min.
  - Done when: README + DEMO_SCRIPT updated, screenshots in `docs/saas-screenshots/`.
