# YARA — pattern matching for malware identification.
# Used by disk-specialist subagent through ./bin/sb.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        yara \
        python3-yara \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

USER nobody:nogroup
WORKDIR /scratch
