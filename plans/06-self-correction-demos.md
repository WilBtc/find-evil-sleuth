# 06 · Self-Correction Demos

> Both self-corrections must be visible in ≤5 min video. This doc fixes the exact reproduction steps so the demo isn't ad-libbed.

## Demo case: SANS LoneWolf

3-image case (disk + memory + pcap). Reasonable size, public, well-documented ground truth.

`scripts/fetch-evidence.sh` downloads, hashes, populates `evidence-samples/lone-wolf/`.

## Pre-flight (off camera, before record)

```
./scripts/fetch-evidence.sh lone-wolf
./scripts/inject-corruption.sh lone-wolf
docker compose -f docker/compose.yaml up -d
./bin/es init
./bin/sb describe vol3 >/dev/null
```

`inject-corruption.sh` (revised after R3/R4 validation 2026-05-06):
```bash
#!/usr/bin/env bash
set -euo pipefail
case_dir="evidence-samples/$1"

# Tool-crash injection #1 — wrong OS family in triage hint
# (vol3 auto-detects profile so a "wrong profile" hint won't crash it;
#  but a wrong-family plugin invocation does crash with a clear signature)
jq '.memory.os_family_hint = "linux"' \
  "$case_dir/manifest.json" > "$case_dir/manifest.json.tmp"
mv "$case_dir/manifest.json.tmp" "$case_dir/manifest.json"

# Pcap-truncation injection #2 — tshark exits 2 with
# "appears to have been cut short in the middle of a packet"
# editcap copies what's recoverable (exit 0 + warning), tshark on
# recovered file exits 0.
pcap="$case_dir/network/lonewolf.pcap"
size=$(stat -c%s "$pcap")
truncate -s $((size - 4096)) "$pcap"

echo "[+] Corruption injected — case is now demo-ready."
```

**Validated 2026-05-06 (pre-build):**
- tshark on truncated pcap → exit 2, stderr `appears to have been cut short in the middle of a packet`. `editcap` recovers (exit 0 with same warning), subsequent tshark on recovered file exits 0.
- vol3 with wrong inputs → exit 1, stderr `Unsatisfied requirement` / `translation layer requirement was not fulfilled` / `symbol table requirement`. Plugin-family mismatch (linux.pslist on Win image) gives the cleanest demo signature.
- **Broker gotcha:** vol3 piped through `tail` masks its exit code (pipe writes 0). Broker MUST NOT pipe vol3 stdout. Use `-o output_dir` instead and read the file.

## Run (on camera)

```
./scripts/investigate.sh evidence-samples/lone-wolf/
```

## Beat sheet (≤ 5 min)

| Time | What's on screen | What narrator says |
|---|---|---|
| 0:00–0:15 | `cat README.md` showing one-command install | "find-evil-sleuth: a Level-5 agentic DFIR system on SIFT, all guardrails architectural." |
| 0:15–0:45 | `docs/architecture.svg` (briefly) | Walk the diagram: hook → broker → podman → Postgres substrate. Mention "every finding traceable to a tool call via `es cite`." |
| 0:45–1:15 | `./scripts/investigate.sh evidence-samples/lone-wolf/` starts. `adw dashboard` in side pane. | "Triage classifies the case. Three specialists fan out in parallel." |
| 1:15–2:30 | Specialists running. `tail -f` the obs event stream in third pane showing `Sleuth.specialist.started` for each. | "Disk uses sleuthkit + plaso, memory uses volatility 3, network uses zeek + suricata + tshark. Every tool call goes through the broker — the agent literally cannot call vol3 directly." |
| 2:30–3:15 | **Self-correction #1 fires.** Memory specialist hits `vol3 windows.malfind` with the wrong profile. obs stream shows `Sleuth.tool.executed exit=1` then `Sleuth.self_correct.attempt strategy=derive_profile` then `windows.info` then `windows.malfind exit=0`. | "Volatility crashed because the profile was wrong. The agent detected the failure, ran windows.info to derive the correct profile, patched its case plan, and retried — autonomously." |
| 3:15–4:00 | **Self-correction #2 fires.** Network specialist hits truncated pcap. obs shows `tshark exit=2` then `Sleuth.self_correct.attempt strategy=editcap_recover` then recovered tshark, with finding `confidence=partial`. | "Pcap is truncated. Agent catches the EOF, runs editcap to recover, completes analysis, and marks affected findings as 'partial confidence' — confirmed findings are distinguished from inferences." |
| 4:00–4:30 | `./bin/es cite F-042` showing full audit JSON — tool, args, hash, offset, MITRE, validation history, Merkle root. | "Every claim in the report is traceable in one command. This is the audit trail criterion." |
| 4:30–4:55 | `cat report.md` scrolling, citations visible | "The narrator is read-only — it can only cite confirmed findings. Best-of-3 with an Opus judge." |
| 4:55–5:00 | `psql sleuth -c "SELECT count(*), validation_status FROM findings GROUP BY 2"` | "Audit substrate is just Postgres — judges can run live SQL. Thank you." |

## Backup plan if a self-correction doesn't fire on take

- Three terminal panes pre-set with the obs stream paused.
- Two pre-recorded backup takes in `submission/video-takes/`.
- If both demos are blocked by tool flakiness on the live take, fall back to recorded run; narrate over it. **But:** rules require live-terminal screencast — so we record three live takes minimum and pick the best.

## Risk: vol3 profile auto-detect

If volatility 3 auto-detects the profile despite our injection, the crash never fires. Mitigation: pin volatility version, pass `--single-location=banners-only` or set env that disables auto. Verify in Phase 4.

## Risk: tshark EOF tolerance

Modern tshark sometimes prints a warning and continues past EOF. Mitigation: chop deeper (8KB instead of 4KB) and verify exit code is non-zero in Phase 4 testing.

## Recording

- Tool: `kooha-recorder` skill, 1080p60, mp4, mic on.
- Three takes minimum. Best take labeled `submission/demo.mp4`. Backup takes kept until submission.
- Final upload: YouTube unlisted, link in Devpost form. Upload at least 24h before deadline (YT processing).
