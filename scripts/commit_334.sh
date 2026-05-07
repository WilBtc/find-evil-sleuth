#!/usr/bin/env bash
git commit -m "feat(3.3.4): network specialist real-evidence run on LoneWolf - 24 confirmed findings

Ran tshark + zeek against M57-Patents PCAP (m57-net-2009-12-06.pcap.gz)
for case lone-wolf-network. Produced 24 confirmed network findings (F-191
through F-214) covering: protocol hierarchy, IP endpoints, DNS, HTTP
requests/responses, TLS/SNI, ICMP, TCP SYN, UDP conversations, ARP,
SMTP, FTP, SMB, TCP expert info, IP host statistics, IRC, TCP/IP
conversation stats, and HTTP file requests.

Key forensic finding: 192.168.1.103 (MAC 00:0b:db:63:5b:d4) transferred
54MB from 198.189.255.76:80 and 19MB from 198.189.255.74:80 - consistent
with IP theft data exfiltration in the M57-Patents scenario.

Acceptance criterion:
  SELECT count(*) FROM findings
  WHERE case_id LIKE 'lone-wolf-%'
    AND specialist='network'
    AND validation_status='confirmed'
  returns 24 (>=20 required)

Scripts added:
- scripts/network_specialist_lone_wolf.sh (steps 1-11)
- scripts/network_specialist_lone_wolf_part2.sh (steps 12-20)
- scripts/confirm_network_findings.sh
- scripts/check_network_findings.sh
- scripts/check_network_confirmed.sh

Generated with Claude Code"
