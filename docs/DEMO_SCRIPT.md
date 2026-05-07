# Demo Script — find-evil-sleuth

Beat-by-beat narration for the ≤5-minute demo video.
Aligned to `plans/06-self-correction-demos.md`.

**Total time budget: 5:00**
**Every claim below is verifiable from the audit DB.**

---

## Pre-flight (off camera)

```bash
./scripts/fetch-evidence.sh lone-wolf
./scripts/inject-corruption.sh lone-wolf        # injects vol3 crash + pcap truncation
docker compose -f docker/compose.yaml up -d
./bin/es init
./bin/sb describe vol3 >/dev/null
```

Three terminal panes pre-arranged:
- **Pane A** (main) — commands
- **Pane B** — `./adw dashboard` (live case progress)
- **Pane C** — `tail -f <obs-event-stream>` (raw broker events)

---

## Beat Sheet

| Clock | Duration | Screen | Narration |
|-------|----------|--------|-----------|
| 0:00 | 0:15 | `cat README.md` — one-command quickstart visible | *"find-evil-sleuth: a Level-5 agentic DFIR system running on SIFT. One command from evidence to auditable report. All guardrails are architectural — the agent literally cannot call a forensic tool outside the broker."* |
| 0:15 | 0:30 | `docs/architecture.svg` open | *"Here's the architecture. A hook fires whenever evidence lands. The ADW driver classifies the case, fans out specialist agents in parallel — disk, memory, network. Each specialist calls tools through the broker only. Every tool call, its stdout hash, and exit code land in Postgres. Every finding cites its tool call. Run `es cite F-042` and you get the full audit chain."* |
| 0:45 | 0:30 | Pane A: `./scripts/investigate.sh evidence-samples/lone-wolf/` starts. Pane B: ADW dashboard animates. | *"Kicking off the LoneWolf case — three-image set from SANS: disk image, Windows memory dump, pcap. Triage classifies in under ten seconds."* |
| 1:15 | 1:15 | Pane C: obs stream scrolling. `Sleuth.specialist.started` events appear for disk, memory, network. Pane B shows three parallel lanes. | *"Three specialists fan out simultaneously. Disk runs sleuthkit and plaso, memory runs Volatility 3, network runs zeek, tshark, and suricata. Every invocation is brokered — arguments are logged before the process starts, so there's no way to issue an unaudited tool call."* |
| 2:30 | 0:45 | **Self-correction #1.** Pane C shows in order: `Sleuth.tool.executed plugin=windows.pslist exit=1` → `Sleuth.self_correct.attempt strategy=derive_profile` → `Sleuth.tool.executed plugin=windows.info exit=0` → `Sleuth.tool.executed plugin=windows.pslist exit=0` | *"Volatility crashed — wrong OS family hint in the manifest. The agent detected exit 1, identified the error signature 'Unsatisfied requirement / translation layer', ran windows.info to derive the correct profile, patched its own case plan, and retried. The whole correction loop is recorded in the DB. Self-corrections are first-class audit events."* |
| 3:15 | 0:45 | **Self-correction #2.** Pane C shows: `Sleuth.tool.executed tool=tshark exit=2 stderr="cut short in the middle of a packet"` → `Sleuth.self_correct.attempt strategy=editcap_recover` → `Sleuth.tool.executed tool=editcap exit=0` → `Sleuth.tool.executed tool=tshark exit=0` | *"Pcap is truncated — tshark exits 2 with 'cut short in the middle of a packet'. Agent catches it, runs editcap to recover what's there, completes the analysis, and marks those findings confidence=partial. Confirmed findings are distinguished from inferences at the row level."* |
| 4:00 | 0:30 | Pane A: `./bin/es cite F-042` — JSON output showing tool, args hash, stdout hash, MITRE ATT&CK tag, validation_status, Merkle root. | *"Every claim in the report is traceable in one command — tool name, exact arguments, stdout hash, offset into the artifact, MITRE tag, validation history, and the Merkle root of the tool-call chain. This is the audit trail criterion."* |
| 4:30 | 0:20 | Browser: `./scripts/saas.sh up` already running — switch to browser at http://127.0.0.1:8932/. Click into the LoneWolf case, then `/findings`, then drill into one finding. | *"And here's the persistent inspector — one command, no notebook required. Every finding is one click away: tool call, exact arguments, stdout hash, Merkle root. The audit chain page shows the tamper-free badge in green. Judges can browse any case, any finding, live."* |
| 4:50 | 0:05 | Pane A: `cat report.md` — first paragraph with [F-NNN] citations visible. | *"The narrator's report — every factual claim cited."* |
| 4:55 | 0:05 | Pane A: `psql sleuth -c "SELECT count(*), validation_status FROM findings GROUP BY 2"` — table printed. | *"Audit substrate is just Postgres — judges can run live SQL right now. Thank you."* |

**Total: 5:00**

---

## Timestamp Verification

| Segment | Start | End | Duration |
|---------|-------|-----|----------|
| Intro / README | 0:00 | 0:15 | 0:15 |
| Architecture diagram | 0:15 | 0:45 | 0:30 |
| Investigation start | 0:45 | 1:15 | 0:30 |
| Specialists running | 1:15 | 2:30 | 1:15 |
| Self-correction #1 (vol3) | 2:30 | 3:15 | 0:45 |
| Self-correction #2 (pcap) | 3:15 | 4:00 | 0:45 |
| `es cite` audit chain | 4:00 | 4:30 | 0:30 |
| Persistent inspector (SaaS) | 4:30 | 4:50 | 0:20 |
| `cat report.md` | 4:50 | 4:55 | 0:05 |
| Closing SQL | 4:55 | 5:00 | 0:05 |
| **Total** | | | **5:00** |

---

## Claims and Their DB Verifications

| Claim | Verification query |
|-------|--------------------|
| Self-correction #1 fired (vol3 derive_profile) | `SELECT * FROM self_corrections WHERE strategy='derive_profile' ORDER BY created_at LIMIT 1;` |
| Self-correction #2 fired (editcap_recover) | `SELECT * FROM self_corrections WHERE strategy='editcap_recover' ORDER BY created_at LIMIT 1;` |
| Partial-confidence findings exist | `SELECT count(*) FROM findings WHERE confidence='partial';` |
| All findings have tool_call citations | `SELECT count(*) FROM findings WHERE tool_call_id IS NULL;` — must return 0 |
| Merkle root present on findings | `SELECT count(*) FROM findings WHERE merkle_root IS NOT NULL;` |
| Validator ran on all findings | `SELECT count(*) FROM findings f LEFT JOIN validation_runs v ON f.id=v.finding_id WHERE v.id IS NULL;` — must return 0 |

---

## Backup Plan

If a self-correction does not fire on the live take:
1. Two pre-recorded backup takes are in `submission/video-takes/`.
2. Pick the best take that shows both self-corrections. Narrate over it.
3. Rules require live-terminal screencast, so record ≥3 live takes and keep the best.

See `plans/06-self-correction-demos.md §Backup plan` for details.
