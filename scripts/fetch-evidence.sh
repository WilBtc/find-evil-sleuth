#!/usr/bin/env bash
# fetch-evidence.sh — Download forensics evidence datasets for find-evil-sleuth.
#
# Usage:
#   ./scripts/fetch-evidence.sh lone-wolf [--dry-run] [--skip-disk] [--skip-memory] [--skip-pcap]
#
# Downloads to: evidence-samples/lone-wolf/
# Writes SHA256 manifest to: evidence-samples/lone-wolf/MANIFEST
#
# Dataset sources:
#   Disk:   2018 Lone Wolf Scenario (Digital Corpora / AWS Open Data)
#           https://digitalcorpora.org/corpora/scenarios/2018-lone-wolf-scenario/
#   Memory: 2018 Lone Wolf memdump.mem (Digital Corpora)
#   PCAP:   2009 M57-Patents network capture (Digital Corpora)
#           https://digitalcorpora.org/corpora/scenarios/m57-patents-scenario/
#           (LoneWolf has no pcap; M57 is the companion network dataset)
#
# All Digital Corpora datasets are freely available under the Open Data terms.
# No authentication required.
#
# Requirements: wget (or curl), sha256sum, python3 (for size formatting only)

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCENARIO="${1:-}"
DEST_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/evidence-samples"

LONEWOLF_S3="https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files"
M57_S3="https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2009-m57-patents/net"

# E01 segments for the LoneWolf disk image (9 files, ~13.5 GB total)
DISK_FILES=(
    "LoneWolf.E01"
    "LoneWolf.E02"
    "LoneWolf.E03"
    "LoneWolf.E04"
    "LoneWolf.E05"
    "LoneWolf.E06"
    "LoneWolf.E07"
    "LoneWolf.E08"
    "LoneWolf.E09"
)

# Single memory dump file (~17 GB)
MEM_FILE="memdump.mem"

# Network capture from M57-Patents (supplementary; LoneWolf has no pcap).
# This is a 149 MB compressed daily capture from the M57 scenario network.
# Stored with URL-encoded colon (%3A).
PCAP_FILE_REMOTE="net-2009-12-06-11%3A59.pcap.gz"
PCAP_FILE_LOCAL="m57-net-2009-12-06.pcap.gz"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
DRY_RUN=false
SKIP_DISK=false
SKIP_MEM=false
SKIP_PCAP=false

shift || true   # consumed SCENARIO
for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY_RUN=true ;;
        --skip-disk) SKIP_DISK=true ;;
        --skip-memory) SKIP_MEM=true ;;
        --skip-pcap) SKIP_PCAP=true ;;
        *) echo >&2 "Unknown flag: $arg"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { echo >&2 "[fetch-evidence] $*"; }
die()  { echo >&2 "[fetch-evidence] ERROR: $*"; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# Download with resume support. Args: URL dest_file
download() {
    local url="$1" dest="$2"
    local fname
    fname="$(basename "$dest")"

    if [[ -f "$dest" ]]; then
        log "  already present: $fname (skipping)"
        return 0
    fi

    log "  downloading: $fname"
    log "    from: $url"

    if command -v wget >/dev/null 2>&1; then
        wget --continue --no-verbose --show-progress \
            --retry-connrefused --tries=3 --timeout=60 \
            -O "${dest}.partial" "$url"
    elif command -v curl >/dev/null 2>&1; then
        curl --retry 3 --retry-delay 5 --location --continue-at - \
            --progress-bar -o "${dest}.partial" "$url"
    else
        die "Neither wget nor curl is available. Install one and retry."
    fi

    mv "${dest}.partial" "$dest"
    log "  saved: $fname"
}

# Compute SHA256 for a file and return it
sha256_of() {
    local f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" | awk '{print $1}'
    else
        die "sha256sum / shasum not found"
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$SCENARIO" in
    lone-wolf|lonewolf) ;;
    "")   die "Usage: $0 lone-wolf [flags]" ;;
    *)    die "Unknown scenario: $SCENARIO  (supported: lone-wolf)" ;;
esac

DEST="${DEST_BASE}/lone-wolf"

if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN — showing what would be downloaded to ${DEST}"
    log ""
    log "Disk segments (${#DISK_FILES[@]} × E01):"
    for f in "${DISK_FILES[@]}"; do
        log "  ${LONEWOLF_S3}/${f}"
    done
    log "Memory dump:"
    log "  ${LONEWOLF_S3}/${MEM_FILE}"
    log "Network capture:"
    log "  ${M57_S3}/${PCAP_FILE_REMOTE}  →  ${PCAP_FILE_LOCAL}"
    log ""
    log "Estimated total: ~31 GB compressed"
    exit 0
fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
    || die "sha256sum or shasum is required but neither was found"
log "Destination: ${DEST}"
mkdir -p "${DEST}"

# ---------------------------------------------------------------------------
# Download disk image (E01 segments)
# ---------------------------------------------------------------------------

if [[ "$SKIP_DISK" == "false" ]]; then
    log ""
    log "=== Disk image (LoneWolf E01 segments) ==="
    for seg in "${DISK_FILES[@]}"; do
        download "${LONEWOLF_S3}/${seg}" "${DEST}/${seg}"
    done
else
    log "(--skip-disk: skipping disk download)"
fi

# ---------------------------------------------------------------------------
# Download memory dump
# ---------------------------------------------------------------------------

if [[ "$SKIP_MEM" == "false" ]]; then
    log ""
    log "=== Memory dump ==="
    download "${LONEWOLF_S3}/${MEM_FILE}" "${DEST}/${MEM_FILE}"
else
    log "(--skip-memory: skipping memory download)"
fi

# ---------------------------------------------------------------------------
# Download network capture (M57-Patents supplementary)
# ---------------------------------------------------------------------------

if [[ "$SKIP_PCAP" == "false" ]]; then
    log ""
    log "=== Network capture (M57-Patents 2009-12-06) ==="
    download "${M57_S3}/${PCAP_FILE_REMOTE}" "${DEST}/${PCAP_FILE_LOCAL}"
else
    log "(--skip-pcap: skipping pcap download)"
fi

# ---------------------------------------------------------------------------
# Build MANIFEST (SHA256)
# ---------------------------------------------------------------------------

log ""
log "=== Building MANIFEST ==="

MANIFEST="${DEST}/MANIFEST"
: > "${MANIFEST}"

{
    echo "# find-evil-sleuth evidence manifest"
    echo "# Scenario: 2018 Lone Wolf (Digital Corpora) + M57-Patents PCAP"
    echo "# Source:   https://digitalcorpora.org/corpora/scenarios/2018-lone-wolf-scenario/"
    echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "#"
    echo "# Format: SHA256  filename  source_url"
    echo ""
} > "${MANIFEST}"

total_bytes=0

add_manifest_entry() {
    local filepath="$1"
    local url="$2"
    local fname
    fname="$(basename "$filepath")"

    if [[ ! -f "$filepath" ]]; then
        log "  MISSING (not downloaded yet): $fname"
        echo "MISSING  ${fname}  ${url}" >> "${MANIFEST}"
        return 0
    fi

    log "  hashing: $fname"
    local hash
    hash="$(sha256_of "$filepath")"

    local size
    size="$(wc -c < "$filepath")"
    total_bytes=$(( total_bytes + size ))

    echo "${hash}  ${fname}  ${url}" >> "${MANIFEST}"
    log "  OK  ${hash:0:16}…  ($(( size / 1048576 )) MiB)"
}

for seg in "${DISK_FILES[@]}"; do
    add_manifest_entry "${DEST}/${seg}" "${LONEWOLF_S3}/${seg}"
done

add_manifest_entry "${DEST}/${MEM_FILE}" "${LONEWOLF_S3}/${MEM_FILE}"
add_manifest_entry "${DEST}/${PCAP_FILE_LOCAL}" "${M57_S3}/${PCAP_FILE_REMOTE}"

{
    echo ""
    echo "# Total bytes: ${total_bytes}"
} >> "${MANIFEST}"

log ""
log "MANIFEST written to ${MANIFEST}"
log "Total bytes on disk: ${total_bytes}  ($(( total_bytes / 1073741824 )) GiB)"

# ---------------------------------------------------------------------------
# Acceptance check
# ---------------------------------------------------------------------------

log ""
log "=== Acceptance check ==="

FAILURES=0

check_file() {
    local f="$1" label="$2"
    if [[ -f "$f" ]]; then
        local sz
        sz="$(wc -c < "$f")"
        log "  PASS  ${label}  ($(( sz / 1048576 )) MiB)"
    else
        log "  FAIL  ${label}  — file not found: $f"
        FAILURES=$(( FAILURES + 1 ))
    fi
}

# Require at least E01 (first segment) as proof of disk presence
check_file "${DEST}/LoneWolf.E01"         "disk    LoneWolf.E01"
check_file "${DEST}/${MEM_FILE}"          "memory  memdump.mem"
check_file "${DEST}/${PCAP_FILE_LOCAL}"   "pcap    ${PCAP_FILE_LOCAL}"

FIVE_GB=$(( 5 * 1024 * 1024 * 1024 ))
if (( total_bytes >= FIVE_GB )); then
    log "  PASS  total size ${total_bytes} bytes ≥ 5 GiB"
elif (( total_bytes > 0 )); then
    log "  WARN  total size ${total_bytes} bytes < 5 GiB (partial download?)"
    # Not fatal — partial downloads are valid during incremental runs
else
    log "  WARN  total size 0 (no files downloaded yet)"
fi

# Verify MANIFEST hashes match on-disk files
log ""
log "=== Verifying SHA256 manifest ==="
HASH_FAILURES=0
while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^# ]] && continue
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^MISSING ]] && continue

    read -r hash fname _rest <<< "$line"
    local_file="${DEST}/${fname}"
    if [[ ! -f "$local_file" ]]; then
        log "  SKIP  ${fname} (not downloaded)"
        continue
    fi
    actual_hash="$(sha256_of "$local_file")"
    if [[ "$actual_hash" == "$hash" ]]; then
        log "  PASS  ${fname}"
    else
        log "  FAIL  ${fname}  expected=${hash:0:16}… got=${actual_hash:0:16}…"
        HASH_FAILURES=$(( HASH_FAILURES + 1 ))
    fi
done < "${MANIFEST}"

if (( HASH_FAILURES > 0 )); then
    die "${HASH_FAILURES} SHA256 mismatch(es) — evidence may be corrupted"
fi

if (( FAILURES > 0 )); then
    die "${FAILURES} required file(s) missing. Re-run without --skip-* flags."
fi

log ""
log "All checks passed."
log "Evidence ready at: ${DEST}"
log ""
