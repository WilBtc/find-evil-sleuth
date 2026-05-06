# Wireshark CLI suite — tshark / editcap / mergecap / capinfos
# Used by network-specialist subagent through ./bin/sb.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        tshark \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# tshark / dumpcap need cap_net_raw to capture live, but for offline pcap
# analysis (our use case) it does not — runs fine as nobody.
USER nobody:nogroup
WORKDIR /scratch
