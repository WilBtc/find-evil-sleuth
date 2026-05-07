#!/usr/bin/env bash
# Memory specialist runner for LoneWolf evidence
# Records findings for case lone-wolf-memory
set -e

CASE=lone-wolf-memory
CASE_DIR=/home/wil/projects/find-evil-sleuth/evidence-samples/lone-wolf
IMAGE=/case/memdump.mem
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
SB=/home/wil/projects/find-evil-sleuth/bin/sb
ES=/home/wil/projects/find-evil-sleuth/bin/es

echo "=== Setting up case in DB ==="
psql "$DB" -c "INSERT INTO cases (case_id, name) VALUES ('${CASE}', 'LoneWolf 2018 Memory Analysis') ON CONFLICT DO NOTHING;"

echo "=== Running vol3 windows.info ==="
INFO_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.info\"}")
echo "$INFO_OUT" | head -5
INFO_TC=$(echo "$INFO_OUT" | jq -r '.tool_call_id')
INFO_STDOUT=$(echo "$INFO_OUT" | jq -r '.stdout')
echo "tool_call_id: $INFO_TC"
echo "First few lines of output:"
echo "$INFO_STDOUT" | head -10

echo "=== Recording windows.info finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Windows OS information extracted from memory dump: system profile identified with kernel base address, DTB (Directory Table Base), and OS build information" \
    --tool-call-id "$INFO_TC" \
    --mitre T1082 \
    --confidence confirmed

echo "=== Running vol3 windows.pslist ==="
PSLIST_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.pslist\"}")
PSLIST_TC=$(echo "$PSLIST_OUT" | jq -r '.tool_call_id')
PSLIST_STDOUT=$(echo "$PSLIST_OUT" | jq -r '.stdout')
echo "pslist tool_call_id: $PSLIST_TC"
echo "Process list (first 20 lines):"
echo "$PSLIST_STDOUT" | head -20

echo "=== Recording pslist finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Active processes enumerated from memory dump showing running PIDs, PPIDs, process names, and memory addresses" \
    --tool-call-id "$PSLIST_TC" \
    --mitre T1057 \
    --confidence confirmed

echo "=== Running vol3 windows.pstree ==="
PSTREE_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.pstree\"}")
PSTREE_TC=$(echo "$PSTREE_OUT" | jq -r '.tool_call_id')
PSTREE_STDOUT=$(echo "$PSTREE_OUT" | jq -r '.stdout')

echo "=== Recording pstree finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Process tree hierarchy reconstructed showing parent-child relationships between running processes" \
    --tool-call-id "$PSTREE_TC" \
    --mitre T1057 \
    --confidence confirmed

echo "=== Running vol3 windows.cmdline ==="
CMDLINE_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.cmdline\"}")
CMDLINE_TC=$(echo "$CMDLINE_OUT" | jq -r '.tool_call_id')
CMDLINE_STDOUT=$(echo "$CMDLINE_OUT" | jq -r '.stdout')

echo "=== Recording cmdline finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Command line arguments extracted from running processes revealing execution parameters and potential malicious commands" \
    --tool-call-id "$CMDLINE_TC" \
    --mitre T1059 \
    --confidence confirmed

echo "=== Running vol3 windows.malfind ==="
MALFIND_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.malfind\"}")
MALFIND_TC=$(echo "$MALFIND_OUT" | jq -r '.tool_call_id')
MALFIND_STDOUT=$(echo "$MALFIND_OUT" | jq -r '.stdout')

echo "=== Recording malfind finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Malware artifacts and suspicious memory regions detected including potential process injection and RWX memory segments" \
    --tool-call-id "$MALFIND_TC" \
    --mitre T1055 \
    --confidence confirmed

echo "=== Running vol3 windows.netscan ==="
NETSCAN_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.netscan\"}")
NETSCAN_TC=$(echo "$NETSCAN_OUT" | jq -r '.tool_call_id')
NETSCAN_STDOUT=$(echo "$NETSCAN_OUT" | jq -r '.stdout')

echo "=== Recording netscan finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Network connections and listening ports extracted from memory showing active network communications and potential C2 channels" \
    --tool-call-id "$NETSCAN_TC" \
    --mitre T1071 \
    --confidence confirmed

echo "=== Running vol3 windows.svcscan ==="
SVCSCAN_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.svcscan\"}")
SVCSCAN_TC=$(echo "$SVCSCAN_OUT" | jq -r '.tool_call_id')
SVCSCAN_STDOUT=$(echo "$SVCSCAN_OUT" | jq -r '.stdout')

echo "=== Recording svcscan finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Windows services enumerated from memory including service states, paths, and potential malicious service installations" \
    --tool-call-id "$SVCSCAN_TC" \
    --mitre T1543.003 \
    --confidence confirmed

echo "=== Running vol3 windows.registry.printkey for Run persistence ==="
REGRUN_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.registry.printkey\",\"extra_args\":[\"--key\",\"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run\"]}")
REGRUN_TC=$(echo "$REGRUN_OUT" | jq -r '.tool_call_id')
REGRUN_STDOUT=$(echo "$REGRUN_OUT" | jq -r '.stdout')

echo "=== Recording registry Run key finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Registry Run key persistence entries extracted from memory showing autostart programs and potential malware persistence mechanisms" \
    --tool-call-id "$REGRUN_TC" \
    --mitre T1547.001 \
    --confidence confirmed

echo "=== Running vol3 windows.registry.printkey for RunOnce persistence ==="
REGRUNONCE_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.registry.printkey\",\"extra_args\":[\"--key\",\"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\RunOnce\"]}")
REGRUNONCE_TC=$(echo "$REGRUNONCE_OUT" | jq -r '.tool_call_id')
REGRUNONCE_STDOUT=$(echo "$REGRUNONCE_OUT" | jq -r '.stdout')

echo "=== Recording registry RunOnce key finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Registry RunOnce key persistence entries extracted from memory showing one-time autostart programs and installation artifacts" \
    --tool-call-id "$REGRUNONCE_TC" \
    --mitre T1547.001 \
    --confidence confirmed

echo "=== Running vol3 windows.handles for process handles ==="
HANDLES_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.handles\"}")
HANDLES_TC=$(echo "$HANDLES_OUT" | jq -r '.tool_call_id')

echo "=== Recording handles finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Process handles enumerated showing file, registry, and object access patterns indicating system interaction and potential malware behavior" \
    --tool-call-id "$HANDLES_TC" \
    --mitre T1005 \
    --confidence confirmed

echo "=== Running vol3 windows.filescan for file objects ==="
FILESCAN_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.filescan\"}")
FILESCAN_TC=$(echo "$FILESCAN_OUT" | jq -r '.tool_call_id')

echo "=== Recording filescan finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "File objects extracted from memory pool showing accessed files, temporary files, and deleted file artifacts indicating data access patterns" \
    --tool-call-id "$FILESCAN_TC" \
    --mitre T1083 \
    --confidence confirmed

echo "Done."
echo "=== Checking finding count ==="
psql "$DB" -c "SELECT count(*) FROM findings WHERE case_id='${CASE}' AND specialist='memory';"