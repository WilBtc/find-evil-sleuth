# Plaso (log2timeline) — super-timeline generation.
# log2timeline.py + psort.py used by disk-specialist subagent through ./bin/sb.
FROM python:3.11-slim-bookworm

ARG PLASO_VERSION=20231231

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        libfuse2 \
        libewf-dev \
        libssl-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        plaso==${PLASO_VERSION} \
        dfvfs \
        artifacts

USER nobody:nogroup
WORKDIR /scratch
