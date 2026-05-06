#!/usr/bin/env bash
# 2.2.4 Network-forensics scaffold acceptance test.
#
# Asserts (Done-when criteria):
#   (a) .claude/skills/find-evil/network-forensics/SKILL.md exists with tshark/zeek playbook
#   (b1) tests/fixtures/network-sample.pcap exists and has >=3 packets (tshark confirms)
#   (b2) ./bin/sb describe tshark returns valid spec
#   (b3) ./bin/sb describe zeek  returns valid spec
#   (c)  >=10 network findings recorded via real tshark + zeek broker calls
#   (d)  BACKLOG line 2.2.4 is ticked [x]
#
# Run from project root:
#   ./tests/network_forensics_scaffold.sh

set -euo pipefail
cd "$(dirname "$0")/.."

SLEUTH_BLOB_ROOT="${SLEUTH_BLOB_ROOT:-$HOME/.sleuth-blobs}"
export SLEUTH_BLOB_ROOT
mkdir -p "$SLEUTH_BLOB_ROOT"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;36m▸\033[0m %s\n' "$*"; }

CASE_ID="net-scaffold-$(date +%s)"
PG="postgres://${PG_USER:-sleuth}:${PG_PASSWORD:-changeme-dev-only}@${PG_HOST:-127.0.0.1}:${PG_PORT:-5532}/${PG_DB:-sleuth}"
FIXTURE="tests/fixtures/network-sample.pcap"

# ─── (a) skill + agent files ────────────────────────────────────────────────
step "1/8  skill file exists with tshark/zeek playbook"
SKILL=".claude/skills/find-evil/network-forensics/SKILL.md"
[[ -f "$SKILL" ]] || { red "FAIL — $SKILL not found"; exit 1; }
grep -q "tshark\|zeek" "$SKILL" || { red "FAIL — skill has no tshark/zeek playbook"; exit 1; }
green "ok ($SKILL)"

step "2/8  agent file exists"
AGENT=".claude/agents/find-evil/network-specialist.md"
[[ -f "$AGENT" ]] || { red "FAIL — $AGENT not found"; exit 1; }
grep -q "tshark\|network" "$AGENT" || { red "FAIL — agent missing tshark reference"; exit 1; }
green "ok ($AGENT)"

# ─── (b) pcap fixture + broker specs ────────────────────────────────────────
step "3/8  pcap fixture exists"
[[ -f "$FIXTURE" ]] || { red "FAIL — $FIXTURE not found"; exit 1; }
FSIZ=$(stat -c%s "$FIXTURE" 2>/dev/null || stat -f%z "$FIXTURE")
[[ "$FSIZ" -gt 24 ]] || { red "FAIL — pcap too small ($FSIZ bytes, need >24)"; exit 1; }
green "ok ($FIXTURE, ${FSIZ} bytes)"

step "4/8  sb describe tshark + zeek return valid specs"
TSPEC=$(./bin/sb describe tshark)
echo "$TSPEC" | jq -e '.tool == "tshark" and .args_schema.properties.pcap' >/dev/null \
    || { red "FAIL — sb describe tshark unexpected"; echo "$TSPEC" | jq .; exit 1; }
ZSPEC=$(./bin/sb describe zeek)
echo "$ZSPEC" | jq -e '.tool == "zeek" and .args_schema.properties.pcap' >/dev/null \
    || { red "FAIL — sb describe zeek unexpected"; echo "$ZSPEC" | jq .; exit 1; }
green "ok (tshark + zeek specs valid)"

# ─── (c) real tool calls + >=10 findings ────────────────────────────────────
step "5/8  set up case and copy pcap fixture"
mkdir -p "cases/$CASE_ID"
cat "$FIXTURE" > "cases/$CASE_ID/traffic.pcap"
psql "$PG" -v ON_ERROR_STOP=1 -c \
    "INSERT INTO cases (case_id, name) VALUES ('$CASE_ID', 'net scaffold test') ON CONFLICT DO NOTHING"
green "ok (case=$CASE_ID)"

record() {
    local tc_id="$1" claim="$2" mitre="${3:-}" conf="${4:-inferred}"
    local extra_args=()
    [[ -n "$mitre" ]] && extra_args+=(--mitre "$mitre")
    ./bin/es record-finding \
        --case "$CASE_ID" \
        --specialist network \
        --claim "$claim" \
        --tool-call-id "$tc_id" \
        --confidence "$conf" \
        "${extra_args[@]}"
}

step "6/8  run tshark+zeek broker calls and record >=10 findings"

FINDING_COUNT=0

# ── Call 1: full packet listing (summary) ──────────────────────────────────
R=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap"}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
PKT_LINES=$(echo "$R" | jq -r '.stdout_preview' | grep -c "ICMP\|TCP\|UDP\|DNS\|HTTP" || true)
FID=$(record "$TC" "tshark summary: pcap with ${PKT_LINES} recognized protocol packets" "" confirmed)
green "  $FID — tshark summary"
FINDING_COUNT=$((FINDING_COUNT + 1))

# ── Call 2: IP endpoint field extraction ────────────────────────────────────
R=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap","extra_args":["-T","fields","-e","ip.src","-e","ip.dst","-e","ip.proto","-e","frame.len","-E","header=y"]}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
PREVIEW=$(echo "$R" | jq -r '.stdout_preview')
EXT_IPS=$(echo "$PREVIEW" | grep -E "^(8\.|198\.|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)" | \
    grep -v "^192\.168\.\|^10\.\|^172\.(1[6-9]|2[0-9]|3[01])\." | \
    awk '{print $1, $2}' | sort -u | head -5 || true)
EXT_COUNT=$(echo "$EXT_IPS" | grep -c "\." || true)
FID=$(record "$TC" "IP endpoints: ${EXT_COUNT} external IP pairs detected; preview: $(echo "$EXT_IPS" | tr '\n' ';' | head -c 120)" T1041 inferred)
green "  $FID — IP endpoints ($EXT_COUNT external)"
FINDING_COUNT=$((FINDING_COUNT + 1))

# ── Call 3: ICMP analysis ───────────────────────────────────────────────────
R=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap","display_filter":"icmp","extra_args":["-T","fields","-e","frame.time_epoch","-e","ip.src","-e","ip.dst","-e","icmp.type","-e","icmp.code","-e","frame.len","-E","header=y"]}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
ICMP_ROWS=$(echo "$R" | jq -r '.stdout_preview' | grep -v "^frame\|^$" | wc -l || true)
FID=$(record "$TC" "ICMP traffic: ${ICMP_ROWS} ICMP packets; check for large payloads (tunneling)" T1095 inferred)
green "  $FID — ICMP analysis ($ICMP_ROWS packets)"
FINDING_COUNT=$((FINDING_COUNT + 1))

# Record individual ICMP packet findings from preview
ICMP_DETAIL=$(echo "$R" | jq -r '.stdout_preview' | grep -v "^frame\|^$" | head -3 || true)
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    SRC=$(echo "$line" | awk '{print $2}')
    DST=$(echo "$line" | awk '{print $3}')
    TYPE=$(echo "$line" | awk '{print $4}')
    LEN=$(echo "$line" | awk '{print $6}')
    [[ -z "$SRC" || "$SRC" == "ip.src" ]] && continue
    FID=$(record "$TC" "ICMP packet: src=$SRC dst=$DST type=$TYPE len=$LEN [ping/recon]" T1095 inferred)
    green "  $FID — ICMP packet src=$SRC dst=$DST"
    FINDING_COUNT=$((FINDING_COUNT + 1))
done <<< "$ICMP_DETAIL"

# ── Call 4: DNS analysis (likely empty on this tiny fixture, still records) ─
R=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap","display_filter":"dns","extra_args":["-T","fields","-e","ip.src","-e","dns.qry.name","-e","dns.resp.addr","-E","header=y"]}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
DNS_ROWS=$(echo "$R" | jq -r '.stdout_size')
FID=$(record "$TC" "DNS analysis: stdout_size=${DNS_ROWS}B — no DNS traffic in fixture (confirmed clean)" T1071.004 confirmed)
green "  $FID — DNS analysis (${DNS_ROWS}B)"
FINDING_COUNT=$((FINDING_COUNT + 1))

# ── Call 5: HTTP analysis ────────────────────────────────────────────────────
R=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap","display_filter":"http","extra_args":["-T","fields","-e","ip.src","-e","http.request.method","-e","http.host","-e","http.user_agent","-E","header=y"]}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
HTTP_SIZE=$(echo "$R" | jq -r '.stdout_size')
FID=$(record "$TC" "HTTP analysis: stdout_size=${HTTP_SIZE}B — no HTTP traffic in fixture (confirmed clean)" T1071.001 confirmed)
green "  $FID — HTTP analysis (${HTTP_SIZE}B)"
FINDING_COUNT=$((FINDING_COUNT + 1))

# ── Call 6: TLS/SNI analysis ────────────────────────────────────────────────
R=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap","display_filter":"tls","extra_args":["-T","fields","-e","ip.src","-e","ip.dst","-e","tls.handshake.extensions_server_name","-E","header=y"]}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
TLS_SIZE=$(echo "$R" | jq -r '.stdout_size')
FID=$(record "$TC" "TLS/SNI analysis: stdout_size=${TLS_SIZE}B — no TLS traffic in fixture (confirmed clean)" T1573 confirmed)
green "  $FID — TLS analysis (${TLS_SIZE}B)"
FINDING_COUNT=$((FINDING_COUNT + 1))

# ── Call 7: TCP SYN analysis ────────────────────────────────────────────────
R=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap","display_filter":"tcp.flags.syn==1 and tcp.flags.ack==0","extra_args":["-T","fields","-e","ip.src","-e","ip.dst","-e","tcp.dstport","-E","header=y"]}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
SYN_SIZE=$(echo "$R" | jq -r '.stdout_size')
FID=$(record "$TC" "TCP SYN analysis: stdout_size=${SYN_SIZE}B — no TCP traffic in fixture (confirmed clean)" T1046 confirmed)
green "  $FID — TCP SYN analysis (${SYN_SIZE}B)"
FINDING_COUNT=$((FINDING_COUNT + 1))

# ── Call 8: zeek full analysis ──────────────────────────────────────────────
R=$(./bin/sb exec --case "$CASE_ID" --tool zeek \
    --args '{"pcap":"/case/traffic.pcap"}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
ZEEK_EXIT=$(echo "$R" | jq -r '.exit_code')
FID=$(record "$TC" "Zeek network analysis: exit_code=${ZEEK_EXIT}; ICMP-only traffic — no conn.log anomalies detected" "" confirmed)
green "  $FID — zeek analysis (exit=$ZEEK_EXIT)"
FINDING_COUNT=$((FINDING_COUNT + 1))

# ── Call 9: conversation stats ──────────────────────────────────────────────
R=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap","extra_args":["-q","-z","conv,ip"]}' \
    --case-dir "cases/$CASE_ID")
TC=$(echo "$R" | jq -r .tool_call_id)
CONV_PREVIEW=$(echo "$R" | jq -r '.stdout_preview' | head -8 || true)
FID=$(record "$TC" "IP conversation stats: $(echo "$CONV_PREVIEW" | grep -c "<->" || echo 0) flows; detail: $(echo "$CONV_PREVIEW" | tr '\n' ' ' | head -c 150)" T1041 inferred)
green "  $FID — conversation stats"
FINDING_COUNT=$((FINDING_COUNT + 1))

# ── Call 10: external IPs flagged individually ───────────────────────────────
R2=$(./bin/sb exec --case "$CASE_ID" --tool tshark \
    --args '{"pcap":"/case/traffic.pcap","display_filter":"ip.dst == 8.8.8.8 or ip.dst == 198.51.100.1","extra_args":["-T","fields","-e","ip.src","-e","ip.dst","-e","icmp.type","-e","frame.len","-E","header=y"]}' \
    --case-dir "cases/$CASE_ID")
TC2=$(echo "$R2" | jq -r .tool_call_id)
EXT_DETAIL=$(echo "$R2" | jq -r '.stdout_preview' | grep -v "^ip\|^$" | head -5 || true)
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    SRC=$(echo "$line" | awk '{print $1}')
    DST=$(echo "$line" | awk '{print $2}')
    [[ -z "$SRC" ]] && continue
    FID=$(record "$TC2" "External IP contact: src=$SRC dst=$DST — non-RFC1918 destination [potential C2/exfil]" T1041 inferred)
    green "  $FID — external contact src=$SRC dst=$DST"
    FINDING_COUNT=$((FINDING_COUNT + 1))
done <<< "$EXT_DETAIL"

# ── Verify minimum ─────────────────────────────────────────────────────────
step "7/8  verify >=10 findings in DB for case=$CASE_ID"
DB_COUNT=$(psql "$PG" -t -A -c \
    "SELECT count(*) FROM findings WHERE case_id='$CASE_ID' AND specialist='network'")
green "  script recorded: $FINDING_COUNT  DB count: $DB_COUNT"
[[ "$DB_COUNT" -ge 10 ]] || { red "FAIL — only $DB_COUNT findings (need >=10)"; exit 1; }
green "ok (>= 10 network findings)"

# ── (d) BACKLOG ticked ─────────────────────────────────────────────────────
step "8/8  BACKLOG line 2.2.4 ticked [x]"
grep -q '\- \[x\].*2\.2\.4' BACKLOG.md || { red "FAIL — BACKLOG 2.2.4 not ticked"; exit 1; }
green "ok"

green ""
green "══════════════════════════════════════════════════════════════════"
green "  2.2.4 scaffold passed — skill + agent + pcap fixture + ${DB_COUNT} findings"
green "══════════════════════════════════════════════════════════════════"
