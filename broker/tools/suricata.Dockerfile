# Suricata — network IDS with Emerging Threats Open rules baked in.
# Used by network-specialist subagent through ./bin/sb.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        suricata \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fetch ET Open rules (no-cost, BSD-licensed) and pre-install them.
# Falls back gracefully if built without network access.
RUN mkdir -p /var/lib/suricata/rules \
    && ( curl -fsSL --retry 3 \
           "https://rules.emergingthreats.net/open/suricata-7.0.3/emerging.rules.tar.gz" \
           -o /tmp/et-rules.tar.gz \
       && tar -xzf /tmp/et-rules.tar.gz -C /var/lib/suricata/rules --strip-components=1 \
       && rm /tmp/et-rules.tar.gz \
       && echo "ET rules installed" \
       ) || echo "ET rules fetch skipped (no-net build)"

USER nobody:nogroup
WORKDIR /scratch
