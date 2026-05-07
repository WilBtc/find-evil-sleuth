#!/usr/bin/env bash
# inject-corruption.sh — Deterministic, idempotent, reversible evidence corruption
# for the find-evil-sleuth self-correction demo (task 3.4.1).
#
# Usage:
#   ./scripts/inject-corruption.sh lone-wolf            # inject corruption
#   ./scripts/inject-corruption.sh lone-wolf --restore  # restore clean state
#
# Two injections for the LoneWolf demo case:
#
#   #1  manifest.json memory.os_family_hint = "linux"
#       Causes the memory specialist to invoke linux.pslist on the Windows image,
#       which exits 1 with "Unsatisfied requirement …". The derive_profile
#       self-correction strategy then runs windows.info, derives the correct OS
#       family, patches the plan, and retries windows.malfind — exit 0.
#
#   #2  pcap file truncation (-4096 bytes)
#       tshark exits 2 with "appears to have been cut short in the middle of a
#       packet". The editcap_recover strategy runs editcap to salvage the
#       readable prefix, reruns tshark against the recovered file (exit 0), and
#       marks affected findings confidence=partial.
#
# Idempotency: the script saves originals as <file>.orig on first inject and
# refuses to truncate twice. --restore copies .orig back and removes them.
# If .orig is absent on --restore, the script exits 0 (already clean).
#
# Requirements: jq, stat, truncate (GNU coreutils), bash ≥4.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    echo >&2 "Usage: $0 <scenario> [--restore]"
    echo >&2 "  scenario: lone-wolf"
    echo >&2 "  --restore: reverse the corruption, return evidence to clean state"
    exit 1
}

SCENARIO="${1:-}"
RESTORE=false

shift || true
for arg in "$@"; do
    case "$arg" in
        --restore) RESTORE=true ;;
        *) echo >&2 "Unknown flag: $arg"; usage ;;
    esac
done

case "$SCENARIO" in
    lone-wolf|lonewolf) ;;
    "") usage ;;
    *) echo >&2 "Unknown scenario: $SCENARIO (supported: lone-wolf)"; exit 1 ;;
esac

CASE_DIR="${PROJECT_ROOT}/evidence-samples/lone-wolf"

if [[ ! -d "$CASE_DIR" ]]; then
    echo >&2 "[inject] ERROR: evidence directory not found: ${CASE_DIR}"
    echo >&2 "[inject]        Run ./scripts/fetch-evidence.sh lone-wolf first."
    exit 1
fi

MANIFEST="${CASE_DIR}/manifest.json"
PCAP="${CASE_DIR}/m57-net-2009-12-06.pcap.gz"

# ---------------------------------------------------------------------------
# --restore path
# ---------------------------------------------------------------------------

if [[ "$RESTORE" == "true" ]]; then
    echo "[inject] Restoring LoneWolf evidence to clean state …"

    restored=0

    if [[ -f "${MANIFEST}.orig" ]]; then
        cp "${MANIFEST}.orig" "${MANIFEST}"
        rm "${MANIFEST}.orig"
        echo "[inject]   manifest.json restored (os_family_hint → windows)"
        restored=$(( restored + 1 ))
    else
        echo "[inject]   manifest.json — no .orig found, already clean (skipping)"
    fi

    if [[ -f "${PCAP}.orig" ]]; then
        cp "${PCAP}.orig" "${PCAP}"
        rm "${PCAP}.orig"
        echo "[inject]   pcap restored to original size"
        restored=$(( restored + 1 ))
    else
        echo "[inject]   pcap — no .orig found, already clean (skipping)"
    fi

    echo "[inject] Done. ${restored} file(s) restored."
    exit 0
fi

# ---------------------------------------------------------------------------
# Inject path
# ---------------------------------------------------------------------------

echo "[inject] Injecting corruption into LoneWolf evidence …"

# --- #1: manifest.json — os_family_hint corruption ---

if [[ ! -f "$MANIFEST" ]]; then
    echo >&2 "[inject] ERROR: manifest.json not found: ${MANIFEST}"
    echo >&2 "[inject]        Expected file created by fetch-evidence.sh / this repo."
    exit 1
fi

current_hint="$(jq -r '.memory.os_family_hint // "missing"' "${MANIFEST}")"

if [[ "$current_hint" == "linux" ]]; then
    echo "[inject]   manifest.json already corrupted (os_family_hint=linux) — idempotent skip"
elif [[ -f "${MANIFEST}.orig" ]]; then
    echo "[inject]   manifest.json .orig already exists — idempotent skip"
else
    cp "${MANIFEST}" "${MANIFEST}.orig"
    jq '.memory.os_family_hint = "linux"' "${MANIFEST}" > "${MANIFEST}.tmp"
    mv "${MANIFEST}.tmp" "${MANIFEST}"
    echo "[inject]   manifest.json → os_family_hint set to 'linux' (was: ${current_hint})"
fi

# --- #2: pcap truncation ---

if [[ ! -f "$PCAP" ]]; then
    echo >&2 "[inject] ERROR: pcap file not found: ${PCAP}"
    echo >&2 "[inject]        Run ./scripts/fetch-evidence.sh lone-wolf first."
    exit 1
fi

pcap_size="$(stat -c%s "${PCAP}")"
truncated_size=$(( pcap_size - 4096 ))

if [[ -f "${PCAP}.orig" ]]; then
    echo "[inject]   pcap .orig already exists — idempotent skip (current size: ${pcap_size})"
elif (( pcap_size <= 4096 )); then
    echo >&2 "[inject] ERROR: pcap too small (${pcap_size} bytes) to truncate safely"
    exit 1
else
    cp "${PCAP}" "${PCAP}.orig"
    truncate -s "${truncated_size}" "${PCAP}"
    echo "[inject]   pcap truncated: ${pcap_size} → ${truncated_size} bytes (-4096)"
fi

echo ""
echo "[inject] ✓ Corruption injected — LoneWolf case is demo-ready."
echo "[inject]   Injection #1: memory.os_family_hint = 'linux' (triggers derive_profile)"
echo "[inject]   Injection #2: pcap truncated by 4096 bytes (triggers editcap_recover)"
echo "[inject]"
echo "[inject]   Run investigate.sh and check: psql sleuth -c 'SELECT * FROM self_corrections'"
echo "[inject]   To restore:  ./scripts/inject-corruption.sh lone-wolf --restore"
