#!/usr/bin/env bash
# fetch-dataset.sh — pull a public DFIR dataset into evidence-samples/<id>/
#
# Usage:
#   ./scripts/fetch-dataset.sh <dataset> [<dest-dir>]
#
# Datasets (free + redistributable):
#   lone-wolf        — SANS LoneWolf 2018 + M57 pcap (delegates to fetch-evidence.sh)
#   cridex           — Volatility Cridex banking-trojan memory dump (~36 MB)
#   cfreds-hacking   — NIST CFReDS Hacking Case (~4.5 GB NTFS image)
#   nitroba          — Nitroba 2008 university stalker pcap (~800 MB)
#   dfrws-2008-mem   — DFRWS 2008 memory analysis challenge (~1.3 GB)
#   m57-jean         — Digital Corpora M57 Jean Windows XP image (~5 GB)
#   honeynet-6       — Honeynet Forensic Challenge 6 banking troubles (~600 MB)
#
# Each entry verifies SHA256 (when published upstream) and writes a MANIFEST.
# Failures exit non-zero so the SaaS spawn surfaces them via the case log.
#
# Sources (all public, no auth):
#   Volatility samples       https://github.com/volatilityfoundation/volatility/wiki/Memory-Samples
#   NIST CFReDS              https://cfreds.nist.gov/all/NIST/HackingCase
#   Digital Corpora          https://digitalcorpora.org/corpora/scenarios/
#   Nitroba                  https://digitalcorpora.org/corpora/scenarios/nitroba-university-harassment-scenario/
#   DFRWS                    https://dfrws.org/forensic-challenges/
#   Honeynet                 https://www.honeynet.org/challenges/

set -euo pipefail

DATASET="${1:?Usage: $0 <dataset> [dest-dir]}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_BASE="${REPO_ROOT}/evidence-samples"
DEST="${2:-${DEST_BASE}/${DATASET}}"

mkdir -p "$DEST"

log() { printf '[fetch-dataset] %s\n' "$*" >&2; }
die() { printf '[fetch-dataset] ERROR: %s\n' "$*" >&2; exit 1; }

fetch_one() {
    # fetch_one <url> <dest-filename> [<sha256>]
    local url="$1" name="$2" want_sha="${3:-}"
    local out="${DEST}/${name}"
    if [[ -f "$out" ]]; then
        log "already present: $name ($(stat -c%s "$out") bytes)"
    else
        log "pulling $url"
        wget --continue --no-verbose --show-progress --retry-connrefused \
             --tries=3 --timeout=120 -O "${out}.partial" "$url" \
             || die "wget failed for $url"
        mv "${out}.partial" "$out"
    fi
    if [[ -n "$want_sha" ]]; then
        local got
        got="$(sha256sum "$out" | awk '{print $1}')"
        if [[ "$got" != "$want_sha" ]]; then
            die "SHA256 mismatch for $name: want=$want_sha got=$got"
        fi
        log "SHA256 ✓ $name"
    fi
    printf '%s  %s\n' "$(sha256sum "$out" | awk '{print $1}')" "$name" >> "${DEST}/MANIFEST.tmp"
}

unpack_zip() { (cd "$DEST" && unzip -o -q "$1") || die "unzip $1 failed"; }
unpack_gz()  { gunzip -k -f "$1" || die "gunzip $1 failed"; }
unpack_7z()  { (cd "$DEST" && 7z x -y "$1" >/dev/null) || die "7z extract $1 failed"; }

: > "${DEST}/MANIFEST.tmp"

case "$DATASET" in
  lone-wolf)
    log "delegating to fetch-evidence.sh lone-wolf"
    exec "${REPO_ROOT}/scripts/fetch-evidence.sh" lone-wolf
    ;;

  cridex)
    # Banking trojan memory image used by Volatility tutorials.
    # Mirror: digitalcorpora's volatility samples bucket.
    fetch_one \
      "https://downloads.volatilityfoundation.org/releases/2.6/Cridex.zip" \
      "Cridex.zip"
    unpack_zip "Cridex.zip"
    # Renames cridex.vmem → memdump.mem so vol3 specialist treats it as the canonical mem image.
    if [[ -f "${DEST}/cridex.vmem" && ! -f "${DEST}/memdump.mem" ]]; then
        mv "${DEST}/cridex.vmem" "${DEST}/memdump.mem"
    fi
    ;;

  cfreds-hacking)
    # NIST CFReDS Hacking Case — Windows XP NTFS image with ground-truth
    # answers. ~4.5 GB. Distributed as 8 split files .e01..e08 (EnCase format).
    log "NIST CFReDS Hacking Case (~4.5 GB across 8 split EWF files)"
    for n in 01 02 03 04 05 06 07 08; do
      fetch_one \
        "https://cfreds-archive.nist.gov/Hacking_Case/SCHARDT.E${n}" \
        "SCHARDT.E${n}"
    done
    log "EWF split images fetched. Use ewfmount to access; sleuthkit handles E0x natively."
    ;;

  nitroba)
    # 2008 University of Nitroba harassment investigation — Wireshark pcap.
    # Public. ~800 MB.
    fetch_one \
      "https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2008-nitroba/nitroba.pcap" \
      "traffic.pcap"
    ;;

  dfrws-2008-mem)
    # DFRWS 2008 Memory Analysis Challenge — historic but well-documented.
    # 1.3 GB Windows XP memory image.
    fetch_one \
      "https://dfrws.org/sites/default/files/2008-dfrws-memory.zip" \
      "dfrws-mem.zip"
    unpack_zip "dfrws-mem.zip"
    # Find any *.mem and rename
    if compgen -G "${DEST}/*.mem" > /dev/null; then
        for f in "${DEST}"/*.mem; do
            [[ "$f" != "${DEST}/memdump.mem" ]] && mv "$f" "${DEST}/memdump.mem"
            break
        done
    fi
    ;;

  m57-jean)
    # M57-Patents Jean's machine — Windows XP user, patent-leak scenario.
    # ~5 GB raw image.
    fetch_one \
      "https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2009-m57-patents/disk-images/jo-2009-12-11-002.E01" \
      "disk.E01"
    fetch_one \
      "https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2009-m57-patents/disk-images/jo-2009-12-11-002.E02" \
      "disk.E02"
    ;;

  honeynet-6)
    # Honeynet Forensic Challenge 6 — banking troubles (pcap + memory).
    log "Honeynet Forensic Challenge 6 — banking troubles"
    fetch_one \
      "https://honeynet.org/files/SoTM34/sotm34.tar.gz" \
      "sotm34.tar.gz" || die "sotm34.tar.gz download failed (Honeynet may have moved the asset)"
    (cd "$DEST" && tar -xzf sotm34.tar.gz) || die "tar extract failed"
    ;;

  *)
    die "Unknown dataset: $DATASET. Run with no args to see the list."
    ;;
esac

mv "${DEST}/MANIFEST.tmp" "${DEST}/MANIFEST"
log "DONE  dataset=${DATASET}  dest=${DEST}"
ls -la "$DEST" | tail -10
