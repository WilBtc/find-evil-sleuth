# Zeek — network analysis framework with Emerging Threats open rules baked in.
# Used by network-specialist subagent through ./bin/sb.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        gnupg \
        curl \
        ca-certificates \
    && curl -fsSL https://download.opensuse.org/repositories/security:/zeek/Debian_12/Release.key \
        | gpg --dearmor -o /usr/share/keyrings/zeek-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/zeek-archive-keyring.gpg] https://download.opensuse.org/repositories/security:/zeek/Debian_12/ /" \
        > /etc/apt/sources.list.d/zeek.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        zeek \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/zeek/bin:${PATH}"

# Fetch ET Open rules (no-cost, BSD-licensed subset) for offline pcap analysis.
# Stored under /opt/zeek/share/zeek/site/intel/ as a plain-text intel feed.
RUN mkdir -p /opt/zeek/share/zeek/site/intel \
    && curl -fsSL "https://rules.emergingthreats.net/open/zeek/emerging-all.rules.gz" \
        -o /tmp/et-zeek.rules.gz \
    && gunzip /tmp/et-zeek.rules.gz \
    && mv /tmp/et-zeek.rules /opt/zeek/share/zeek/site/intel/emerging-all.rules \
    || echo "ET rules fetch skipped (no-net build) — rules absent"

USER nobody:nogroup
WORKDIR /scratch
