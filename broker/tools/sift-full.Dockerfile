# find-evil-sleuth/sift-full — the FULL SANS SIFT distribution (not a slim build).
#
# Provenance:
#   Base = docker.io/digitalsleuth/sift-remnux:latest, the SIFT+REMnux bundle
#   published by digitalsleuth (Corey Forman), the current active maintainer of
#   the SANS SIFT Workstation. This is the real, full distribution (~15 GB),
#   shipping the complete forensic toolchain — Sleuth Kit, Volatility 2 & 3,
#   Plaso/log2timeline, Zeek, YARA, bulk_extractor, and the REMnux malware set.
#
# Why a thin derived layer:
#   SIFT/REMnux ship Volatility 3 as `vol3` (and Volatility 2 as `vol.py`).
#   We add a `vol` compatibility wrapper so the documented acceptance command
#   `vol -V` resolves, and stamp provenance labels. No tools are added or
#   removed — this is the upstream distribution verbatim plus one shim.
#
# Build:  ./scripts/fetch-sift.sh        (pulls base, builds this, verifies)
FROM docker.io/digitalsleuth/sift-remnux:latest

LABEL org.opencontainers.image.title="find-evil-sleuth/sift-full" \
      org.opencontainers.image.description="Full SANS SIFT + REMnux distribution (digitalsleuth)" \
      org.opencontainers.image.source="https://hub.docker.com/r/digitalsleuth/sift-remnux" \
      org.find-evil-sleuth.base-digest="sha256:f5ed937d05744ac14b0d5806198b456be0f50fddb80ce482e2da7a4ca8a59bc4"

# `vol` compatibility shim -> Volatility 3 (vol3). `vol.py` (Volatility 2) is left intact.
RUN printf '%s\n' \
      '#!/usr/bin/env bash' \
      '# SIFT/REMnux ship Volatility 3 as vol3; provide `vol` for compatibility.' \
      'if [[ "$1" == "-V" || "$1" == "--version" ]]; then' \
      '  vol3 --help 2>&1 | grep -m1 "Volatility 3 Framework"' \
      'else' \
      '  exec vol3 "$@"' \
      'fi' > /usr/local/bin/vol \
    && chmod +x /usr/local/bin/vol
