# Skill: network-forensics

## Mission

Perform deep forensic analysis of network captures for a given case using
`tshark` and `zeek`. Extract host conversations, suspicious connections,
protocol anomalies, DNS/HTTP/TLS IOCs, and traffic statistics. Record every
finding via `./bin/es` with a valid `tool_call_id` from `./bin/sb`. Do NOT
read evidence directly — all tool access goes through `./bin/sb exec`.

## Inputs

- `CASE_ID` — env var or argument; e.g. `net-forensics-001`
- `/case/` — evidence root (read-only via broker)
- One or more pcap/pcapng files: `.pcap`, `.pcapng`, `.cap`

## Outputs

- ≥10 `findings` rows in Postgres (inserted via `./bin/es record-finding`)
- Optional AGE graph edges (NetworkEndpoint/Connection nodes) via `./bin/es graph`

## Step-by-step Playbook

### Step 0 — Ensure case exists in DB

```bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth -c "
  INSERT INTO cases (case_id, name)
  VALUES ('<CASE_ID>', '<CASE_ID>')
  ON CONFLICT DO NOTHING;
"
```

### Step 1 — Packet count and protocol summary with tshark

Run a packet count and protocol hierarchy to understand the capture:

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","extra_args":["-q","-z","proto,colinfo,ip,ip"]}'
```

Then get the full protocol hierarchy:

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","extra_args":["-q","-z","io,phs"]}'
```

Parse stdout for total packet count, unique protocols, top talkers.
Record a summary finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "Capture summary: <N> packets; protocols: <list>; duration: <secs>s" \
  --tool-call-id <UUID from sb exec output> \
  --confidence confirmed
```

### Step 2 — Unique host conversations (IP endpoints)

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","extra_args":["-q","-z","ip_hosts,tree"]}'
```

Alternatively use field extraction:

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","extra_args":["-T","fields","-e","ip.src","-e","ip.dst","-e","ip.proto","-e","frame.len","-E","header=y"]}'
```

Parse for:
- External IPs (non-RFC1918: not 10.x, 172.16-31.x, 192.168.x)
- High packet-count pairs (possible data exfil or C2 beacon)
- Unusual protocol numbers (not 1=ICMP, 6=TCP, 17=UDP)

Record a finding per suspicious host pair:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "Host conversation: src=<ip> dst=<ip> proto=<proto> bytes=<n> [external/suspicious]" \
  --tool-call-id <UUID> \
  --mitre T1041 \
  --confidence inferred
```

### Step 3 — DNS analysis

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","display_filter":"dns","extra_args":["-T","fields","-e","frame.time_epoch","-e","ip.src","-e","dns.qry.name","-e","dns.resp.addr","-E","header=y"]}'
```

Look for:
- High-entropy domain names (DGA indicators): length > 15, low vowel ratio
- Unusual TLDs (.xyz, .top, .pw, .cc, .tk)
- DNS-over-non-53 (query to port != 53)
- Repeated NXDOMAIN responses (DGA beacon failure)
- Long subdomain strings (DNS tunneling: > 50 chars)

Record a finding per suspicious DNS query:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "Suspicious DNS: src=<ip> query=<name> resolved=<ip|NXDOMAIN> [DGA|tunnel|unusual-TLD]" \
  --tool-call-id <UUID> \
  --mitre T1071.004 \
  --confidence inferred
```

### Step 4 — HTTP analysis

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","display_filter":"http","extra_args":["-T","fields","-e","frame.time_epoch","-e","ip.src","-e","ip.dst","-e","http.request.method","-e","http.host","-e","http.request.uri","-e","http.user_agent","-E","header=y"]}'
```

Look for:
- Suspicious User-Agent strings (PowerShell, curl, python-requests, empty)
- POST requests to non-standard ports (not 80/443/8080)
- Requests with no Referer but high frequency
- Downloads of executable extensions (.exe, .dll, .ps1, .vbs, .bat)
- C2 patterns: regular beaconing, short URIs, base64 in URI

Record a finding per suspicious HTTP request:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "Suspicious HTTP: src=<ip> method=<M> host=<host> uri=<uri> ua=<agent>" \
  --tool-call-id <UUID> \
  --mitre T1071.001 \
  --confidence inferred
```

### Step 5 — TLS/SSL certificate analysis

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","display_filter":"tls.handshake.type == 11","extra_args":["-T","fields","-e","ip.src","-e","ip.dst","-e","tls.handshake.certificate","-e","x509sat.uTF8String","-E","header=y"]}'
```

Also check SNI values:

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","display_filter":"tls.handshake.extensions_server_name","extra_args":["-T","fields","-e","ip.src","-e","ip.dst","-e","tls.handshake.extensions_server_name","-E","header=y"]}'
```

Look for:
- Self-signed certificates (issuer == subject)
- Certificate validity far in future or expired
- SNI mismatch with destination IP's rDNS
- Connections with no SNI but valid TLS (potential malware)

Record a finding per suspicious TLS session:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "Suspicious TLS: src=<ip> dst=<ip> sni=<name|none> cert=<issuer>/<subject>" \
  --tool-call-id <UUID> \
  --mitre T1573 \
  --confidence inferred
```

### Step 6 — ICMP and unusual protocol analysis

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","display_filter":"icmp","extra_args":["-T","fields","-e","frame.time_epoch","-e","ip.src","-e","ip.dst","-e","icmp.type","-e","icmp.code","-e","frame.len","-E","header=y"]}'
```

Look for:
- ICMP packets with large payloads (> 64 bytes, possible tunneling)
- ICMP type 13 (timestamp) or type 17 (address mask) — reconnaissance
- High-volume ICMP to external IPs (flood / covert channel)
- Non-standard ICMP codes

Record a finding per suspicious ICMP pattern:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "Suspicious ICMP: src=<ip> dst=<ip> type=<t> code=<c> payload_len=<n> [tunnel|recon|flood]" \
  --tool-call-id <UUID> \
  --mitre T1095 \
  --confidence inferred
```

### Step 7 — TCP connection anomalies

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","display_filter":"tcp.flags.syn==1 and tcp.flags.ack==0","extra_args":["-T","fields","-e","frame.time_epoch","-e","ip.src","-e","ip.dst","-e","tcp.dstport","-E","header=y"]}'
```

Look for:
- Port scanning (many SYN to different ports from same source)
- Connections to unusual high ports (> 49152, random ephemeral)
- SYN floods (many SYN with no SYN-ACK responses)
- RST storms (many RST packets)

Record a finding per suspicious TCP pattern:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "TCP anomaly: src=<ip> dst=<ip>:<port> flags=<flags> [scan|flood|unusual-port]" \
  --tool-call-id <UUID> \
  --mitre T1046 \
  --confidence inferred
```

### Step 8 — Zeek network analysis (supplementary)

```bash
./bin/sb exec --case <CASE_ID> --tool zeek \
  --args '{"pcap":"/case/traffic.pcap"}'
```

Zeek generates structured logs. Parse stdout for:
- `conn.log` entries: unusual connection states, long durations, large bytes
- `dns.log` entries: high query frequency, NXDOMAIN patterns
- `http.log` entries: unusual status codes, large responses
- `ssl.log` entries: self-signed certs, JA3 fingerprints

Record a finding for each significant zeek observation:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "Zeek observation: <log_type> uid=<uid> src=<ip> dst=<ip>:<port> detail=<desc>" \
  --tool-call-id <UUID> \
  --mitre <ID> \
  --confidence inferred
```

### Step 9 — Flow statistics and top talkers

```bash
./bin/sb exec --case <CASE_ID> --tool tshark \
  --args '{"pcap":"/case/traffic.pcap","extra_args":["-q","-z","conv,ip"]}'
```

Parse for:
- Top talker pairs by bytes (exfil candidates)
- Long-duration connections (persistent C2)
- Asymmetric flows (large upload vs. download ratio)

Record a finding for each suspicious flow:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist network \
  --claim "Network flow: src=<ip> dst=<ip> bytes_sent=<n> bytes_recv=<n> duration=<s>s [exfil|C2|asymmetric]" \
  --tool-call-id <UUID> \
  --mitre T1041 \
  --confidence inferred
```

## Self-Correction Protocol

If `tshark` exits non-zero (corrupted pcap header, truncated capture):

1. Try `editcap` to recover: `{"input":"/case/traffic.pcap","output":"/scratch/traffic-recovered.pcap"}`.
2. Re-run the failed step against the recovered file.
3. Record a finding noting the repair action.

## Minimum findings target

You MUST produce at least 10 `findings` rows before exiting. Each finding must have:
- A non-empty `claim` describing what was found
- A `tool_call_id` from an actual `./bin/sb exec` call
- A `specialist` value of `network`

If you reach Step 7 with fewer than 10 findings, run additional tshark passes:
- UDP conversation stats: `extra_args:["-q","-z","conv,udp"]`
- Expert info: `extra_args:["-q","-z","expert"]`

If the pcap contains no suspicious activity (all traffic looks benign), record one
"no evidence" finding per step (confirmed clean) to meet the 10-finding minimum.

## Error handling

- If a tool call returns exit code != 0, log the `stderr` field from the JSON
  response and continue to the next step. Do NOT stop the investigation.
- If `./bin/sb exec` itself fails (broker down), retry once. If it fails again,
  record a finding noting the tool failure and continue.
- Do NOT modify evidence files.

## Constraints

- MUST use `./bin/sb exec` for every tshark/zeek/editcap call.
- MUST use `./bin/es record-finding` for every finding.
- MUST NOT run `tshark`, `zeek`, or any other binary directly in bash.
- MUST exit 0 when ≥10 findings have been recorded; exit 1 only on fatal error.

## Tool budget

Budget: 15 broker calls per capture. Priority order:
1. tshark protocol hierarchy (1 call)
2. tshark IP endpoint field extraction (1 call)
3. tshark DNS analysis (1 call)
4. tshark HTTP analysis (1 call)
5. tshark TLS SNI analysis (1 call)
6. tshark ICMP analysis (1 call)
7. tshark TCP SYN analysis (1 call)
8. zeek full analysis (1 call)
9. tshark conversation stats (1 call)
10. tshark expert info if needed (1 call)

## MITRE ATT&CK quick reference

| Observation | MITRE ID |
|---|---|
| Data exfiltration over network | T1041 |
| HTTP C2 communication | T1071.001 |
| DNS C2 / tunneling | T1071.004 |
| Encrypted C2 channel | T1573 |
| Non-application layer protocol (ICMP tunnel) | T1095 |
| Port scanning / network service discovery | T1046 |
| Remote service exploitation via network | T1210 |
| Lateral movement via SMB/RPC | T1021 |
| Credential access via network sniffing | T1040 |
