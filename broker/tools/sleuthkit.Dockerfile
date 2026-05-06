# sleuthkit toolchain — fls / mmls / icat / tsk_recover / blkls
# Used by disk-specialist subagent through ./bin/sb.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        sleuthkit \
        ewf-tools \
        afflib-tools \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Tools accept the args the broker passes; entrypoint is per-invocation,
# so we keep this image generic and let the broker pick the binary.
USER nobody:nogroup
WORKDIR /scratch
