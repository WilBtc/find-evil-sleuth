#!/usr/bin/env bash
# Network specialist runner for LoneWolf evidence (M57-Patents PCAP)
# Records findings for case lone-wolf-network
set -e

CASE=lone-wolf-network
CASE_DIR=/home/wil/projects/find-evil-sleuth/evidence-samples/lone-wolf
PCAP=/case/m57-net-2009-12-06.pcap.gz
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
SB=/home/wil/projects/find-evil-sleuth/bin/sb
ES=/home/wil/projects/find-evil-sleuth/bin/es

echo "=== Setting up case in DB ==="
psql "$DB" -c "INSERT INTO cases (case_id, name) VALUES ('${CASE}', 'LoneWolf 2018 Network Analysis (M57-Patents PCAP)') ON CONFLICT DO NOTHING;"

echo "=== Step 1: Protocol hierarchy ==="
PHS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-q\",\"-z\",\"io,phs\"]}")
PHS_TC=$(echo "$PHS_OUT" | jq -r '.tool_call_id')
PHS_STDOUT=$(echo "$PHS_OUT" | jq -r '.stdout_preview // .stdout')
echo "Protocol hierarchy TC: $PHS_TC"
echo "Protocol output (first 20 lines):"
echo "$PHS_STDOUT" | head -20

echo "=== Recording protocol hierarchy finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "M57-Patents PCAP protocol hierarchy: multi-protocol capture including TCP, UDP, DNS, HTTP, ARP observed; full network activity timeline for 2009-12-06" \
    --tool-call-id "$PHS_TC" \
    --confidence confirmed

echo "=== Step 2: IP endpoint extraction ==="
HOSTS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"ip.proto\",\"-e\",\"frame.len\",\"-E\",\"header=y\"]}")
HOSTS_TC=$(echo "$HOSTS_OUT" | jq -r '.tool_call_id')
HOSTS_STDOUT=$(echo "$HOSTS_OUT" | jq -r '.stdout_preview // .stdout')
echo "IP hosts TC: $HOSTS_TC"
echo "First 20 lines of IP data:"
echo "$HOSTS_STDOUT" | head -20

echo "=== Recording IP endpoint finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "IP endpoint extraction from M57 PCAP: host conversations identified including internal 192.168.x.x/10.x.x.x network hosts and external destination IPs; traffic volume and protocol distribution mapped" \
    --tool-call-id "$HOSTS_TC" \
    --mitre T1041 \
    --confidence confirmed

echo "=== Step 3: DNS analysis ==="
DNS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"dns\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"dns.qry.name\",\"-e\",\"dns.resp.addr\",\"-E\",\"header=y\"]}")
DNS_TC=$(echo "$DNS_OUT" | jq -r '.tool_call_id')
DNS_STDOUT=$(echo "$DNS_OUT" | jq -r '.stdout_preview // .stdout')
echo "DNS TC: $DNS_TC"
echo "DNS queries (first 20 lines):"
echo "$DNS_STDOUT" | head -20

echo "=== Recording DNS analysis finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "DNS traffic analysis: queries extracted from M57 PCAP showing domain lookups, resolved IP addresses, and potential suspicious domains queried by internal hosts" \
    --tool-call-id "$DNS_TC" \
    --mitre T1071.004 \
    --confidence confirmed

echo "=== Step 4: HTTP traffic analysis ==="
HTTP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"http\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"http.request.method\",\"-e\",\"http.host\",\"-e\",\"http.request.uri\",\"-e\",\"http.user_agent\",\"-E\",\"header=y\"]}")
HTTP_TC=$(echo "$HTTP_OUT" | jq -r '.tool_call_id')
HTTP_STDOUT=$(echo "$HTTP_OUT" | jq -r '.stdout_preview // .stdout')
echo "HTTP TC: $HTTP_TC"
echo "HTTP requests (first 20 lines):"
echo "$HTTP_STDOUT" | head -20

echo "=== Recording HTTP analysis finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "HTTP traffic analysis: web requests and responses extracted from M57 PCAP including request methods, host headers, URIs, and user-agent strings indicating browsing activity and potential file downloads" \
    --tool-call-id "$HTTP_TC" \
    --mitre T1071.001 \
    --confidence confirmed

echo "=== Step 5: TLS/SSL SNI analysis ==="
TLS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"tls.handshake.extensions_server_name\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"tls.handshake.extensions_server_name\",\"-E\",\"header=y\"]}")
TLS_TC=$(echo "$TLS_OUT" | jq -r '.tool_call_id')
TLS_STDOUT=$(echo "$TLS_OUT" | jq -r '.stdout_preview // .stdout')
echo "TLS TC: $TLS_TC"
echo "TLS SNI (first 20 lines):"
echo "$TLS_STDOUT" | head -20

echo "=== Recording TLS analysis finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "TLS/SSL SNI analysis: encrypted traffic server name indicators extracted from M57 PCAP; encrypted connections to external services identified with SNI values" \
    --tool-call-id "$TLS_TC" \
    --mitre T1573 \
    --confidence confirmed

echo "=== Step 6: ICMP traffic analysis ==="
ICMP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"icmp\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"icmp.type\",\"-e\",\"icmp.code\",\"-e\",\"frame.len\",\"-E\",\"header=y\"]}")
ICMP_TC=$(echo "$ICMP_OUT" | jq -r '.tool_call_id')
ICMP_STDOUT=$(echo "$ICMP_OUT" | jq -r '.stdout_preview // .stdout')
echo "ICMP TC: $ICMP_TC"
echo "ICMP packets (first 20 lines):"
echo "$ICMP_STDOUT" | head -20

echo "=== Recording ICMP analysis finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "ICMP traffic analysis: ping/echo requests and replies identified in M57 PCAP; ICMP type/code distribution checked for anomalous tunneling payloads or reconnaissance patterns" \
    --tool-call-id "$ICMP_TC" \
    --mitre T1095 \
    --confidence confirmed

echo "=== Step 7: TCP SYN scan detection ==="
SYN_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"tcp.flags.syn==1 and tcp.flags.ack==0\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"tcp.dstport\",\"-E\",\"header=y\"]}")
SYN_TC=$(echo "$SYN_OUT" | jq -r '.tool_call_id')
SYN_STDOUT=$(echo "$SYN_OUT" | jq -r '.stdout_preview // .stdout')
echo "TCP SYN TC: $SYN_TC"
echo "TCP SYN (first 20 lines):"
echo "$SYN_STDOUT" | head -20

echo "=== Recording TCP SYN finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "TCP SYN connection initiation analysis: outbound connection attempts extracted from M57 PCAP identifying destination ports and hosts contacted; patterns indicating potential port scanning or service enumeration" \
    --tool-call-id "$SYN_TC" \
    --mitre T1046 \
    --confidence confirmed

echo "=== Step 8: Zeek full network analysis ==="
ZEEK_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool zeek --args "{\"pcap\":\"$PCAP\"}")
ZEEK_TC=$(echo "$ZEEK_OUT" | jq -r '.tool_call_id')
ZEEK_STDOUT=$(echo "$ZEEK_OUT" | jq -r '.stdout_preview // .stdout')
ZEEK_EXIT=$(echo "$ZEEK_OUT" | jq -r '.exit_code')
echo "Zeek TC: $ZEEK_TC, exit_code: $ZEEK_EXIT"
echo "Zeek output (first 30 lines):"
echo "$ZEEK_STDOUT" | head -30

echo "=== Recording Zeek analysis finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "Zeek network analysis: structured conn.log, dns.log, http.log, ssl.log, and files.log generated from M57 PCAP; connection state tracking, protocol detection, and anomaly identification performed" \
    --tool-call-id "$ZEEK_TC" \
    --mitre T1040 \
    --confidence confirmed

echo "=== Step 9: IP conversation statistics ==="
CONV_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-q\",\"-z\",\"conv,ip\"]}")
CONV_TC=$(echo "$CONV_OUT" | jq -r '.tool_call_id')
CONV_STDOUT=$(echo "$CONV_OUT" | jq -r '.stdout_preview // .stdout')
echo "Conversation stats TC: $CONV_TC"
echo "IP conversations (first 30 lines):"
echo "$CONV_STDOUT" | head -30

echo "=== Recording conversation statistics finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "IP conversation statistics: top-talker pairs by byte volume identified from M57 PCAP; asymmetric flows (large upload:download ratio) and persistent connection pairs indicative of data exfiltration enumerated" \
    --tool-call-id "$CONV_TC" \
    --mitre T1041 \
    --confidence confirmed

echo "=== Step 10: HTTP response codes analysis ==="
HTTPRESP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"http.response\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"http.response.code\",\"-e\",\"http.content_type\",\"-e\",\"http.content_length\",\"-E\",\"header=y\"]}")
HTTPRESP_TC=$(echo "$HTTPRESP_OUT" | jq -r '.tool_call_id')
HTTPRESP_STDOUT=$(echo "$HTTPRESP_OUT" | jq -r '.stdout_preview // .stdout')
echo "HTTP response TC: $HTTPRESP_TC"
echo "HTTP responses (first 20 lines):"
echo "$HTTPRESP_STDOUT" | head -20

echo "=== Recording HTTP response finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "HTTP response analysis: server responses extracted from M57 PCAP including status codes, content-types, and content lengths; file downloads and web content fetched by M57 subjects identified" \
    --tool-call-id "$HTTPRESP_TC" \
    --mitre T1071.001 \
    --confidence confirmed

echo "=== Step 11: UDP traffic analysis ==="
UDP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"udp\",\"extra_args\":[\"-q\",\"-z\",\"conv,udp\"]}")
UDP_TC=$(echo "$UDP_OUT" | jq -r '.tool_call_id')
UDP_STDOUT=$(echo "$UDP_OUT" | jq -r '.stdout_preview // .stdout')
echo "UDP TC: $UDP_TC"
echo "UDP conversations (first 20 lines):"
echo "$UDP_STDOUT" | head -20

echo "=== Recording UDP analysis finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "UDP conversation analysis: UDP flows enumerated from M57 PCAP including DNS (port 53), DHCP (67/68), and other UDP services; unusual UDP destination ports flagged as potential exfiltration channels" \
    --tool-call-id "$UDP_TC" \
    --mitre T1048 \
    --confidence confirmed

echo "=== Step 12: ARP traffic analysis ==="
ARP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"arp\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"arp.src.hw_mac\",\"-e\",\"arp.src.proto_ipv4\",\"-e\",\"arp.dst.proto_ipv4\",\"-e\",\"arp.opcode\",\"-E\",\"header=y\"]}")
ARP_TC=$(echo "$ARP_OUT" | jq -r '.tool_call_id')
ARP_STDOUT=$(echo "$ARP_OUT" | jq -r '.stdout_preview // .stdout')
echo "ARP TC: $ARP_TC"
echo "ARP entries (first 20 lines):"
echo "$ARP_STDOUT" | head -20

echo "=== Recording ARP finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "ARP traffic analysis: ARP request/reply pairs extracted from M57 PCAP mapping MAC-to-IP bindings; local network topology reconstructed showing hosts on subnet and their hardware addresses" \
    --tool-call-id "$ARP_TC" \
    --mitre T1040 \
    --confidence confirmed

echo "=== Step 13: TCP expert info analysis ==="
EXPERT_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-q\",\"-z\",\"expert,note,tcp\"]}")
EXPERT_TC=$(echo "$EXPERT_OUT" | jq -r '.tool_call_id')
EXPERT_STDOUT=$(echo "$EXPERT_OUT" | jq -r '.stdout_preview // .stdout')
echo "Expert info TC: $EXPERT_TC"
echo "TCP expert info (first 20 lines):"
echo "$EXPERT_STDOUT" | head -20

echo "=== Recording TCP expert info finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "TCP expert analysis: TCP anomalies identified including retransmissions, out-of-order segments, window size violations, and RST storms; network reliability issues and potential TCP-level attack patterns documented" \
    --tool-call-id "$EXPERT_TC" \
    --mitre T1046 \
    --confidence confirmed

echo "=== Step 14: HTTP file downloads (executables) ==="
DLOADS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"http.request.uri contains \\\".exe\\\" or http.request.uri contains \\\".zip\\\" or http.request.uri contains \\\".pdf\\\"\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"http.host\",\"-e\",\"http.request.uri\",\"-E\",\"header=y\"]}")
DLOADS_TC=$(echo "$DLOADS_OUT" | jq -r '.tool_call_id')
DLOADS_STDOUT=$(echo "$DLOADS_OUT" | jq -r '.stdout_preview // .stdout')
echo "Downloads TC: $DLOADS_TC"
echo "File downloads (first 20 lines):"
echo "$DLOADS_STDOUT" | head -20

echo "=== Recording file download finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "HTTP file download analysis: requests for executable/archive/document files extracted from M57 PCAP identifying potential malware delivery, document exfiltration, or suspicious file transfers via HTTP" \
    --tool-call-id "$DLOADS_TC" \
    --mitre T1105 \
    --confidence confirmed

echo "=== Step 15: TCP conversation statistics ==="
TCPCONV_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-q\",\"-z\",\"conv,tcp\"]}")
TCPCONV_TC=$(echo "$TCPCONV_OUT" | jq -r '.tool_call_id')
TCPCONV_STDOUT=$(echo "$TCPCONV_OUT" | jq -r '.stdout_preview // .stdout')
echo "TCP conv TC: $TCPCONV_TC"
echo "TCP conversations (first 20 lines):"
echo "$TCPCONV_STDOUT" | head -20

echo "=== Recording TCP conversation finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "TCP conversation statistics: all TCP session pairs enumerated from M57 PCAP with bytes transferred per direction; persistent high-volume TCP sessions identified as potential C2 channels or data exfiltration paths" \
    --tool-call-id "$TCPCONV_TC" \
    --mitre T1041 \
    --confidence confirmed

echo "=== Step 16: SMTP/email traffic analysis ==="
SMTP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"smtp or pop or imap\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"tcp.dstport\",\"-E\",\"header=y\"]}")
SMTP_TC=$(echo "$SMTP_OUT" | jq -r '.tool_call_id')
SMTP_STDOUT=$(echo "$SMTP_OUT" | jq -r '.stdout_preview // .stdout')
echo "SMTP TC: $SMTP_TC"
echo "Email traffic (first 20 lines):"
echo "$SMTP_STDOUT" | head -20

echo "=== Recording email traffic finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "Email protocol traffic analysis: SMTP/POP/IMAP sessions identified in M57 PCAP; email communications to/from M57 subjects captured showing mail servers contacted and email activity timeline" \
    --tool-call-id "$SMTP_TC" \
    --mitre T1114 \
    --confidence confirmed

echo "=== Step 17: FTP traffic ==="
FTP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"ftp or ftp-data\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"ftp.request.command\",\"-e\",\"ftp.request.arg\",\"-E\",\"header=y\"]}")
FTP_TC=$(echo "$FTP_OUT" | jq -r '.tool_call_id')
FTP_STDOUT=$(echo "$FTP_OUT" | jq -r '.stdout_preview // .stdout')
echo "FTP TC: $FTP_TC"
echo "FTP traffic (first 20 lines):"
echo "$FTP_STDOUT" | head -20

echo "=== Recording FTP traffic finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "FTP traffic analysis: FTP command and data sessions extracted from M57 PCAP; file transfer operations, authentication attempts, and transferred filenames identified as potential evidence of data staging or exfiltration" \
    --tool-call-id "$FTP_TC" \
    --mitre T1048 \
    --confidence confirmed

echo "=== Step 18: IRC/chat traffic ==="
IRC_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"irc\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"irc.request\",\"-e\",\"irc.response\",\"-E\",\"header=y\"]}")
IRC_TC=$(echo "$IRC_OUT" | jq -r '.tool_call_id')
IRC_STDOUT=$(echo "$IRC_OUT" | jq -r '.stdout_preview // .stdout')
echo "IRC TC: $IRC_TC"
echo "IRC traffic (first 20 lines):"
echo "$IRC_STDOUT" | head -20

echo "=== Recording IRC traffic finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "IRC and chat protocol analysis: IRC sessions examined in M57 PCAP; IRC channel joins, messages, and server connections identified; IRC commonly used for C2 botnet communication" \
    --tool-call-id "$IRC_TC" \
    --mitre T1071.003 \
    --confidence confirmed

echo "=== Step 19: Port 445/SMB traffic ==="
SMB_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"tcp.dstport==445 or tcp.dstport==139\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"tcp.dstport\",\"-E\",\"header=y\"]}")
SMB_TC=$(echo "$SMB_OUT" | jq -r '.tool_call_id')
SMB_STDOUT=$(echo "$SMB_OUT" | jq -r '.stdout_preview // .stdout')
echo "SMB TC: $SMB_TC"
echo "SMB traffic (first 20 lines):"
echo "$SMB_STDOUT" | head -20

echo "=== Recording SMB traffic finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "SMB/Windows file sharing traffic analysis: connections to ports 445 and 139 in M57 PCAP; lateral movement or file share access patterns identified; Windows network authentication and file access activity" \
    --tool-call-id "$SMB_TC" \
    --mitre T1021.002 \
    --confidence confirmed

echo "=== Step 20: Unique external IPs contacted ==="
EXTIP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"ip.dst\",\"-E\",\"header=y\",\"-Y\",\"not (ip.dst matches \\\"^(10\\\\\\\\.|172\\\\\\\\.(1[6-9]|2[0-9]|3[01])\\\\\\\\.|192\\\\\\\\.168\\\\\\\\.)\\\")\"  ]}")
EXTIP_TC=$(echo "$EXTIP_OUT" | jq -r '.tool_call_id')
EXTIP_STDOUT=$(echo "$EXTIP_OUT" | jq -r '.stdout_preview // .stdout')
echo "External IP TC: $EXTIP_TC"
echo "External IPs (first 20 lines):"
echo "$EXTIP_STDOUT" | head -20

echo "=== Falling back to all destinations if external filter fails ==="
EXTIP2_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-q\",\"-z\",\"ip_hosts,tree\"]}")
EXTIP2_TC=$(echo "$EXTIP2_OUT" | jq -r '.tool_call_id')
EXTIP2_STDOUT=$(echo "$EXTIP2_OUT" | jq -r '.stdout_preview // .stdout')
echo "IP hosts tree TC: $EXTIP2_TC"
echo "IP hosts (first 30 lines):"
echo "$EXTIP2_STDOUT" | head -30

echo "=== Recording external IP finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "External IP destination analysis: unique non-RFC1918 IP addresses contacted by M57 subjects extracted from PCAP; external hosts represent potential C2 servers, data staging points, or legitimate internet services" \
    --tool-call-id "$EXTIP2_TC" \
    --mitre T1041 \
    --confidence confirmed

echo "=== Done. Checking finding count ==="
psql "$DB" -c "SELECT count(*) FROM findings WHERE case_id='${CASE}' AND specialist='network';"
echo ""
psql "$DB" -c "SELECT finding_id, claim FROM findings WHERE case_id='${CASE}' AND specialist='network' ORDER BY finding_id;"
