# Demo Run-Sheet — one clean ≤5-minute take

Practical recording guide: exact commands, timing, and narration. Everything below is
**live and reproducible**; the slow parts (a full investigation) are shown *starting*,
not waited on — the completed cases are already in the DB for the live beats.

## Pre-flight (off camera)
```bash
cd ~/projects/find-evil-sleuth
docker compose -f docker/compose.yaml up -d        # substrate (idempotent)
./scripts/saas.sh up                               # inspector on :8932
./bin/es cite F-217 >/dev/null                      # warm the DB connection (so live cite is <100ms)
```
**Terminal layout:** one main pane (commands) + a browser tab at `http://127.0.0.1:8932/`.
Font large. Clear scrollback.

## Beat sheet (target 5:00)

| Clock | Dur | Command(s) on screen | Narration |
|------|-----|----------------------|-----------|
| 0:00 | 0:20 | `bat README.md` (scroll the hero + compliance map) | "find-evil-sleuth: an autonomous DFIR system on the SANS SIFT Workstation. Raw evidence to a cited report, no human in the loop — and every guardrail is *architectural*, not a prompt." |
| 0:20 | 0:35 | `./scripts/investigate.sh ./cases/nitroba/` — let it print `PRE-EXTRACT IOCs … recorded N email + N ip IOC findings`, then Ctrl-C | "Watch it start: before any LLM runs, a deterministic pre-stage carves IOCs straight out of the evidence and records them with full provenance. That part never hallucinates and never needs an API call." |
| 0:55 | 0:25 | `./bin/sb exec --case demo --tool fls --args '{"bad":"x"}'` (shows arg-schema rejection) | "The agent can't touch a forensic tool except through this broker. Bad arguments are rejected by a JSON schema before anything runs. There is no raw-shell path — a PreToolUse hook blocks it." |
| 1:20 | 0:55 | `psql "$DB" -c "SELECT specialist, failed_tool, retry_strategy, retry_tool, succeeded FROM self_corrections WHERE succeeded ORDER BY specialist;"` | **(required self-correction beat)** "Self-correction is first-class. Here the network specialist hit a truncated pcap — tshark exit 2 — recognized the error, ran editcap to recover it, and retried successfully. The memory specialist mis-guessed the OS, ran windows.info to derive the real profile, and recovered. Every correction is an audited row." |
| 2:15 | 0:55 | `./scripts/score_accuracy.py --case nitroba --ground-truth bench/ground-truth/VIGIA-REAL-007/ground_truth.json` | **(the differentiator)** "We don't grade ourselves. This scores our validator-confirmed findings against an external answer key the system never saw — the Nitroba case. 100% of the IOCs that exist in the evidence: the suspect's Gmail account, the internal host. And the benchmark flagged an IOC in the community key that isn't in the capture — so the agent reasons from evidence, it doesn't pattern-match an answer sheet." |
| 3:10 | 0:50 | `time ./bin/es cite F-217` | "Every claim is traceable in one command, under 100 milliseconds: the exact tool, its arguments, the stdout BLAKE3 hash, the MITRE tag, validation history, and the Merkle root of the tool-call chain. That's the audit trail criterion." |
| 4:00 | 0:55 | Browser: `/` → click a case → `/findings` → click a finding → `/audit` (green verify badge) → `/graph` | "And the persistent inspector — one command, no notebook. Browse any case, drill into any finding to its tool call and Merkle root, watch the audit chain verify green, and see the attack graph. Judges can interrogate every case live." |
| 4:55 | 0:05 | `cat cases/nitroba/report.md | head` (cited paragraph) | "The narrator's report — every factual claim carries an [F-NNN] citation. That's find-evil-sleuth." |

## Notes
- `$DB = postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth`
- Use a finding id that exists: `./bin/es cite $(psql "$DB" -tAc "SELECT finding_id FROM findings WHERE case_id='lone-wolf-1778168581' AND validation_status='confirmed' LIMIT 1")`
- If recording the accuracy beat, pick whichever scored case looks strongest at record time
  (`nitroba` network = cleanest single-answer case).
- Keep it under 5:00 — the rules are strict. The self-correction beat and the accuracy beat
  are the two that win; never cut those.
