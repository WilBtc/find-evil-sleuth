# Volatility 3 — memory forensics framework.
# Pinned to a specific tag for reproducibility.
# Plugin family used by demo: windows.{info,pslist,pstree,malfind,netscan,svcscan,registry.printkey}
# NOTE: vol3 stdout exit-code masking gotcha — broker MUST NOT pipe vol3 stdout
# (validated 2026-05-06; see plans/02-broker-design.md). Use -o for output.
FROM python:3.12-slim-bookworm

ARG VOL3_VERSION=2.7.0

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "volatility3==${VOL3_VERSION}"

# Bake the official Windows symbol pack at BUILD time (network is available during
# build). Tool containers run network=none at runtime, so on-demand symbol downloads
# would hang/fail in front of judges. Pre-staging the pack makes vol3 windows.*
# plugins work fully offline. Placed under the vol3 'symbols' search path AND exposed
# via VOLATILITY_SYMBOL_DIR. Read-only (chmod a-w) to preserve evidence integrity.
RUN set -eux; \
    SYM_DIR="$(python3 -c 'import os,volatility3; print(os.path.join(os.path.dirname(volatility3.__file__), "symbols"))')"; \
    mkdir -p "$SYM_DIR" /scratch/symbols; \
    curl -fsSL https://downloads.volatilityfoundation.org/volatility3/symbols/windows.zip \
        -o /tmp/windows.zip; \
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/windows.zip').extractall('$SYM_DIR')"; \
    rm -f /tmp/windows.zip; \
    chmod -R a-w "$SYM_DIR"

# vol3 resolves symbols from its in-package symbols dir (baked above). Also expose the
# scratch path for any explicit override; both are pre-populated / read-only.
ENV VOLATILITY_SYMBOL_DIR=/scratch/symbols

USER nobody:nogroup
WORKDIR /scratch
