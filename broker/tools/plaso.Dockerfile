# Plaso (log2timeline) — super-timeline generation.
# log2timeline.py + psort.py used by disk-specialist subagent through ./bin/sb.
FROM docker.io/log2timeline/plaso:latest

USER root

RUN mkdir -p /scratch && chown nobody:nogroup /scratch

USER nobody:nogroup
WORKDIR /scratch
