#!/usr/bin/env bash
# record-demo.sh — Pre-flight and recording helper for the find-evil-sleuth demo video.
#
# Usage:
#   ./scripts/record-demo.sh preflight     # prepare env, open tmux panes
#   ./scripts/record-demo.sh verify <file> # verify an mp4 is ≤5 min, ≥1080p
#
# Recording steps (human action required):
#   1. Run:  ./scripts/record-demo.sh preflight
#   2. Start Kooha (or OBS): 1080p60, mic ON, desktop audio OFF
#   3. Follow docs/DEMO_SCRIPT.md beat-by-beat
#   4. Save take as submission/take-1.mp4, take-2.mp4, take-3.mp4
#   5. Run:  ./scripts/record-demo.sh verify submission/take-N.mp4
#   6. Copy best take: cp submission/take-N.mp4 submission/demo.mp4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUBMISSION="$ROOT/submission"

usage() {
    echo "Usage: $0 {preflight|verify <file>}"
    exit 1
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage

case "$cmd" in

preflight)
    echo "=== find-evil-sleuth demo pre-flight ==="

    mkdir -p "$SUBMISSION"

    echo ""
    echo "--- 1. Checking Postgres ---"
    if psql sleuth -c "SELECT count(*) FROM findings WHERE validation_status='confirmed'" 2>/dev/null; then
        echo "Postgres OK"
    else
        echo "WARN: Postgres not reachable — run: docker compose -f docker/compose.yaml up -d"
    fi

    echo ""
    echo "--- 2. Checking broker binary ---"
    if [[ -x "$ROOT/bin/sb" ]]; then
        echo "broker OK: $($ROOT/bin/sb --version 2>/dev/null || echo 'binary present')"
    else
        echo "WARN: $ROOT/bin/sb not found — run: ./scripts/build-broker-local.sh"
    fi

    echo ""
    echo "--- 3. Checking evidence-store binary ---"
    if [[ -x "$ROOT/bin/es" ]]; then
        echo "evidence-store OK: $($ROOT/bin/es --version 2>/dev/null || echo 'binary present')"
    else
        echo "WARN: $ROOT/bin/es not found — run: ./scripts/build-es-local.sh"
    fi

    echo ""
    echo "--- 4. Checking evidence samples ---"
    EVIDENCE="$ROOT/evidence-samples"
    if ls "$EVIDENCE/lone-wolf/"*.E0* 2>/dev/null | head -1 | grep -q E0; then
        echo "Evidence images present"
    else
        echo "WARN: LoneWolf images missing — run: ./scripts/fetch-evidence.sh lone-wolf"
    fi

    echo ""
    echo "--- 5. Opening tmux layout ---"
    if command -v tmux &>/dev/null && [[ -z "${TMUX:-}" ]]; then
        echo "Starting new tmux session 'demo'..."
        tmux new-session -d -s demo -x 220 -y 50 2>/dev/null || true
        tmux rename-window -t demo:0 'paneA-main'
        tmux split-window -t demo:0 -h
        tmux send-keys -t demo:0.1 "$ROOT/adw/dashboard.sh 2>/dev/null || echo 'dashboard not yet built'" Enter || true
        tmux split-window -t demo:0.0 -v
        tmux send-keys -t demo:0.2 "tail -f /tmp/obs-events.ndjson 2>/dev/null || echo 'obs stream not yet running'" Enter || true
        echo "Attach with: tmux attach -t demo"
    elif [[ -n "${TMUX:-}" ]]; then
        echo "Already in tmux — manually open Pane B (dashboard) and Pane C (tail obs stream)"
    else
        echo "tmux not found — open three terminal tabs manually:"
        echo "  Pane A: main commands"
        echo "  Pane B: ./adw/dashboard.sh"
        echo "  Pane C: tail -f /tmp/obs-events.ndjson"
    fi

    echo ""
    echo "=== Pre-flight complete ==="
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Open Kooha: Settings → 1080p, 60fps, Mic ON, Desktop audio OFF"
    echo "  2. Follow docs/DEMO_SCRIPT.md beat-by-beat"
    echo "  3. Save takes as submission/take-1.mp4, take-2.mp4, take-3.mp4"
    echo "  4. Run: ./scripts/record-demo.sh verify submission/take-N.mp4"
    echo "  5. Copy best: cp submission/take-N.mp4 submission/demo.mp4"
    ;;

verify)
    file="${2:-}"
    [[ -z "$file" ]] && { echo "Usage: $0 verify <mp4-file>"; exit 1; }
    [[ ! -f "$file" ]] && { echo "ERROR: file not found: $file"; exit 1; }

    echo "=== Verifying $file ==="

    if ! command -v ffprobe &>/dev/null; then
        echo "ERROR: ffprobe not found — install ffmpeg to verify"
        exit 1
    fi

    duration=$(ffprobe -v quiet -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    width=$(ffprobe -v quiet -select_streams v:0 \
        -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    height=$(ffprobe -v quiet -select_streams v:0 \
        -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    fps=$(ffprobe -v quiet -select_streams v:0 \
        -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    has_audio=$(ffprobe -v quiet -select_streams a:0 \
        -show_entries stream=codec_type -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)

    echo "  Duration : ${duration}s"
    echo "  Width    : ${width}px"
    echo "  Height   : ${height}px"
    echo "  FPS      : ${fps}"
    echo "  Audio    : ${has_audio:-NONE}"

    PASS=true

    if (( $(echo "$duration > 300" | bc -l 2>/dev/null || echo 0) )); then
        echo "FAIL: duration ${duration}s exceeds 5 min (300s)"
        PASS=false
    else
        echo "PASS: duration ≤5 min"
    fi

    if [[ "${width:-0}" -ge 1920 && "${height:-0}" -ge 1080 ]]; then
        echo "PASS: resolution ≥1080p (${width}x${height})"
    else
        echo "WARN: resolution ${width}x${height} — target is 1920x1080"
    fi

    if [[ -n "$has_audio" ]]; then
        echo "PASS: audio track present"
    else
        echo "FAIL: no audio track found"
        PASS=false
    fi

    echo ""
    if $PASS; then
        echo "=== VERIFY PASSED — ready to use as submission/demo.mp4 ==="
        exit 0
    else
        echo "=== VERIFY FAILED — re-record or fix the take ==="
        exit 1
    fi
    ;;

*)
    usage
    ;;

esac
