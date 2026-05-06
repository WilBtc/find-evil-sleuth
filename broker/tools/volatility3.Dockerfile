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

# vol3 looks here for downloaded symbols. Bake-baseline a windows symbol pack later;
# for now we let it fetch on first use (network=none would block this — broker spec
# for vol3 may need network='download-once' on first run; see plan 02).
ENV VOLATILITY_SYMBOL_DIR=/scratch/symbols

USER nobody:nogroup
WORKDIR /scratch
