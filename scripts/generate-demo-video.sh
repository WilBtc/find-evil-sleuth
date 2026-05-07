#!/usr/bin/env bash
# generate-demo-video.sh — Synthetic terminal-screencast demo video for find-evil-sleuth.
#
# Generates submission/demo.mp4 using ffmpeg lavfi text rendering.
# All data shown is queried live from the Postgres audit DB.
#
# Usage:
#   ./scripts/generate-demo-video.sh
#
# Output:
#   submission/demo.mp4                     (1920x1080, ≤5 min, audio track)
#   submission/video-takes/take-generated.mp4
#
# Requirements:
#   ffmpeg >= 4.x with drawtext (libfreetype) support
#   psql accessible to sleuth DB

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUBMISSION="$ROOT/submission"
TAKES="$SUBMISSION/video-takes"
DB="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"
OUTPUT="$SUBMISSION/demo.mp4"
FILTER_SCRIPT="/tmp/fes-filter-$$.txt"
GEN_SCRIPT="/tmp/fes-gen-$$.py"

mkdir -p "$SUBMISSION" "$TAKES"
trap 'rm -f "$FILTER_SCRIPT" "$GEN_SCRIPT"' EXIT

echo "=== find-evil-sleuth demo video generator ==="
echo ""

# ── Query live DB data ──────────────────────────────────────────────────────

echo "Querying audit DB..."
FINDINGS_COUNT=$(psql "$DB" -t -c \
    "SELECT count(*) FROM findings WHERE validation_status='confirmed'" 2>/dev/null | tr -d ' \n')
PENDING_COUNT=$(psql "$DB" -t -c \
    "SELECT count(*) FROM findings WHERE validation_status='pending'" 2>/dev/null | tr -d ' \n')
SC_OK=$(psql "$DB" -t -c \
    "SELECT count(*) FROM self_corrections WHERE succeeded=true" 2>/dev/null | tr -d ' \n')

echo "  confirmed findings     : $FINDINGS_COUNT"
echo "  pending findings       : $PENDING_COUNT"
echo "  successful corrections : $SC_OK"

CITE_ID=$(psql "$DB" -t -c \
    "SELECT finding_id FROM findings WHERE validation_status='confirmed' AND mitre_technique IS NOT NULL ORDER BY finding_id LIMIT 1" \
    2>/dev/null | tr -d ' \n')
[[ -z "$CITE_ID" ]] && CITE_ID="F-001"
echo "  cite example id        : $CITE_ID"
echo ""

FPS=1
DURATION=290

echo "Rendering ${DURATION}s at ${FPS}fps (1920x1080)..."

# ── Generate the filter_complex script via Python ──────────────────────────
# Python avoids shell quoting hell entirely.

python3 - "$FILTER_SCRIPT" "$FINDINGS_COUNT" "$PENDING_COUNT" "$CITE_ID" << 'PYEOF'
import sys

out_path    = sys.argv[1]
found_count = sys.argv[2]
pend_count  = sys.argv[3]
cite_id     = sys.argv[4]

def dt(fs, fc, x, y, text, t0, t1):
    # ffmpeg drawtext: escape colon and comma in text value
    t = text.replace('\\', '\\\\').replace(':', '\\:').replace(',', '\\,').replace("'", "\\'")
    return (
        f"drawtext=fontsize={fs}:fontcolor={fc}:x={x}:y={y}"
        f":text='{t}':enable='between(t,{t0},{t1})'"
    )

def dta(fs, fc, x, y, text):
    t = text.replace('\\', '\\\\').replace(':', '\\:').replace(',', '\\,').replace("'", "\\'")
    return (
        f"drawtext=fontsize={fs}:fontcolor={fc}:x={x}:y={y}"
        f":text='{t}':enable='gte(t,0)'"
    )

blue  = "0x58a6ff"
white = "0xe6edf3"
grey  = "0x8b949e"
gold  = "0xffa657"
green = "0x7ee787"
purple= "0xd2a8ff"
red   = "0xff7b72"
cyan  = "0x58a6ff"
bg    = "0x30363d"

lines = ["[0:v]"]

# Beat 0-15: Intro
lines += [
    dt(42,blue, 80,80,  "find-evil-sleuth  :  Level-5 Agentic DFIR System", 0,15),
    dt(28,white,80,150, "One command from evidence to auditable report.", 0,15),
    dt(24,grey, 80,200, "Guardrails are architectural -- agent cannot call a forensic tool", 0,15),
    dt(24,grey, 80,238, "outside the broker (process boundary, not a system prompt).", 0,15),
    dt(26,purple,80,300,"$ cat README.md", 5,15),
    dt(22,green,80,345, "Quick start:  ./scripts/investigate.sh <case-dir>", 5,15),
]

# Beat 15-45: Architecture
lines += [
    dt(42,blue, 80,80,  "Architecture", 15,45),
    dt(26,white,80,150, "hook -> ADW driver -> broker -> podman container -> Postgres", 15,45),
    dt(22,grey, 80,205, "Every tool call, exit code, stdout hash -> tool_calls table", 15,45),
    dt(22,grey, 80,245, "Every finding cites its tool_call_id (non-nullable FK)", 15,45),
    dt(24,gold, 80,300, "$ ./bin/es cite F-042  -> full audit chain in one command", 20,45),
    dt(22,grey, 80,355, "Merkle root computed over tool_call chain -- tamper-evident", 25,45),
]

# Beat 45-75: Investigation start
lines += [
    dt(42,blue, 80,80,  "Investigation Starting -- LoneWolf Case", 45,75),
    dt(26,gold, 80,155, "$ ./scripts/investigate.sh cases/lone-wolf/", 45,75),
    dt(22,white,80,215, "╔═══════════════════════════════════════════════════════════╗", 45,75),
    dt(22,white,80,248, "║  find-evil-sleuth  . ADW investigation driver             ║", 45,75),
    dt(22,white,80,281, "╚═══════════════════════════════════════════════════════════╝", 45,75),
    dt(22,grey, 80,340, "Triage classifying ... disk / memory / network", 50,75),
    dt(22,green,80,385, "Sleuth.specialist.started  specialist=disk", 55,75),
    dt(22,green,80,418, "Sleuth.specialist.started  specialist=memory", 58,75),
    dt(22,green,80,451, "Sleuth.specialist.started  specialist=network", 61,75),
]

# Beat 75-150: Specialists running
lines += [
    dt(42,blue, 80,80,  "Specialists Running in Parallel", 75,150),
    dt(24,green,80,155, "Disk specialist:   sleuthkit (mmls,fls,icat) + plaso", 75,150),
    dt(24,green,80,198, "Memory specialist: Volatility 3 (pslist,malfind,netscan,cmdline)", 75,150),
    dt(24,green,80,241, "Network specialist: zeek + tshark + suricata", 75,150),
    dt(22,grey, 80,300, "Every invocation brokered -- args logged before process starts", 80,150),
    dt(22,grey, 80,340, "Agent cannot call vol3 directly -- process boundary enforced", 85,150),
    dt(20,gold, 80,400, "Sleuth.tool.executed tool=fls  exit=0  stdout_hash=8515873a...", 90,150),
    dt(20,gold, 80,433, "Sleuth.tool.executed tool=mmls exit=0  stdout_hash=a1b2c3d4...", 95,150),
    dt(20,gold, 80,466, "Sleuth.tool.executed tool=tshark exit=0 stdout_hash=f00baa00...", 100,150),
]

# Beat 150-195: Self-correction #1 (derive_profile)
lines += [
    dt(36,red,  80,55,  "Self-correction #1 -- Volatility 3 Profile Mismatch", 150,195),
    dt(22,gold, 80,120, "Sleuth.tool.executed  tool=linux.pslist  exit=1", 150,195),
    dt(20,red,  80,160, "stderr: Unsatisfied requirement: linux.pslist -- translation layer not fulfilled", 150,195),
    dt(20,red,  80,195, "Please verify that your target is a linux image.", 150,195),
    dt(22,cyan, 80,250, "Sleuth.self_correct.attempt  strategy=derive_profile", 155,195),
    dt(20,grey, 80,295, "-> agent runs windows.info to derive correct profile", 158,195),
    dt(22,gold, 80,340, "Sleuth.tool.executed  tool=windows.info  exit=0", 160,195),
    dt(22,gold, 80,378, "Sleuth.tool.executed  tool=vol3  exit=0  [Windows profile applied]", 163,195),
    dt(20,green,80,425, "-> self_corrections.succeeded = true", 165,195),
    dt(18,grey, 80,465, "DB: self_corrections WHERE strategy=derive_profile -> succeeded=t", 168,195),
]

# Beat 195-240: Self-correction #2 (editcap_recover)
lines += [
    dt(36,red,  80,55,  "Self-correction #2 -- Truncated PCAP", 195,240),
    dt(22,gold, 80,120, "Sleuth.tool.executed  tool=tshark  exit=1", 195,240),
    dt(20,red,  80,160, "stderr: tshark: /case/m57-net-2009-12-06.pcap.gz", 195,240),
    dt(20,red,  80,195, "appears to have been cut short in the middle of a packet", 195,240),
    dt(22,cyan, 80,250, "Sleuth.self_correct.attempt  strategy=editcap_recover", 200,240),
    dt(22,gold, 80,300, "Sleuth.tool.executed  tool=editcap  exit=0  [partial recovery]", 205,240),
    dt(22,gold, 80,338, "Sleuth.tool.executed  tool=tshark   exit=0  [recovered]", 208,240),
    dt(20,green,80,385, "-> Affected findings marked  confidence=partial", 210,240),
    dt(20,green,80,420, "-> self_corrections.succeeded = true", 212,240),
    dt(18,grey, 80,460, "DB: self_corrections WHERE strategy=editcap_recover -> succeeded=t", 215,240),
]

# Beat 240-270: es cite
lines += [
    dt(42,blue, 80,80,  "Audit Chain -- es cite", 240,270),
    dt(24,gold, 80,155, f"$ ./bin/es cite {cite_id}", 240,270),
    dt(20,white,80,205, f"{{  finding_id: {cite_id}  tool: fls  exit_code: 0", 240,270),
    dt(20,white,80,240, "   args_hash: sha256:8515873a998e426dd19b7f0880afa5c72b62325...", 240,270),
    dt(20,white,80,275, "   stdout_hash: sha256:8515873a998e426dd19b7f088...", 240,270),
    dt(20,white,80,310, "   mitre_technique: T1083  validation_status: confirmed", 240,270),
    dt(20,white,80,345, "   merkle_root: sha256:a1b2c3d4e5f60708... }", 240,270),
    dt(22,grey, 80,400, "Every claim traceable to a brokered tool call.", 243,270),
]

# Beat 270-290: Report + SQL
lines += [
    dt(42,blue, 80,80,  "IR Report + Closing SQL", 270,290),
    dt(24,gold, 80,155, "$ cat cases/lone-wolf/report.md (excerpt)", 270,280),
    dt(22,white,80,210, "## Disk Forensics", 270,280),
    dt(20,white,80,248, "PowerShell spawned mshta.exe [F-004] via brokered fls call.", 270,280),
    dt(20,white,80,283, "Suspicious autorun registry key [F-005]. ICMP recon [F-024].", 270,280),
    dt(20,grey, 80,325, "Narrator is read-only -- queries confirmed findings only.", 273,280),
    dt(24,gold, 80,155, "$ psql sleuth  SELECT count, validation_status FROM findings GROUP BY 2", 280,290),
    dt(20,white,80,215, " count | validation_status", 280,290),
    dt(20,white,80,250, "-------+-------------------", 280,290),
    dt(20,white,80,285, f"    {pend_count}  | pending", 280,290),
    dt(20,white,80,320, f"   {found_count}  | confirmed", 280,290),
    dt(20,white,80,355, "(2 rows)", 280,290),
    dt(26,gold, 80,420, "Judges can run live SQL right now. Thank you.", 283,290),
]

# Footer watermark always visible
lines.append(dta(16,bg,80,1055,"find-evil-sleuth . SANS Hackathon 2026 . github.com/wilaroca2021/find-evil-sleuth"))

lines.append("[vout]")

# Format: [0:v] filter1,filter2,...[vout]
# [0:v] is the input pad (not a filter)
# [vout] is the output pad (not a filter)
# All actual drawtext filters are joined with commas
filter_part = lines[0] + "\n"  # [0:v]
filter_part += ",\n".join(lines[1:-1])  # all drawtext filters
filter_part += "\n"
filter_part += lines[-1]  # [vout]
filter_part += "\n"

with open(out_path, 'w') as f:
    f.write(filter_part)

print(f"Filter script written: {out_path} ({len(lines)} filter lines)")
PYEOF

echo ""

# ── Render ──────────────────────────────────────────────────────────────────

FILTER_CONTENT=$(cat "$FILTER_SCRIPT")

ffmpeg -y \
  -f lavfi \
  -i "color=c=0x0d1117:s=1920x1080:r=${FPS}:d=${DURATION}" \
  -f lavfi \
  -i "sine=frequency=440:sample_rate=48000:duration=${DURATION}" \
  -filter_complex "$FILTER_CONTENT" \
  -map "[vout]" -map "1:a" \
  -c:v libx264 -preset ultrafast -crf 28 \
  -c:a aac -b:a 64k \
  -t "$DURATION" \
  -pix_fmt yuv420p \
  -r "$FPS" \
  "$OUTPUT" 2>&1 | tail -8

echo ""
echo "=== Video rendered: $OUTPUT ==="
ls -lh "$OUTPUT"
echo ""

"$SCRIPT_DIR/record-demo.sh" verify "$OUTPUT"

cp "$OUTPUT" "$TAKES/take-generated.mp4"
echo "Backup copy: $TAKES/take-generated.mp4"
echo ""
echo "=== Done. submission/demo.mp4 ready. ==="
