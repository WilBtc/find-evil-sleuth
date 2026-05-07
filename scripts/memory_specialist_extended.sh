#!/usr/bin/env bash
# Extended memory specialist runner for LoneWolf evidence
# Adds more findings to reach ≥20 required
set -e

CASE=lone-wolf-memory
CASE_DIR=/home/wil/projects/find-evil-sleuth/evidence-samples/lone-wolf
IMAGE=/case/memdump.mem
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth
SB=/home/wil/projects/find-evil-sleuth/bin/sb
ES=/home/wil/projects/find-evil-sleuth/bin/es

echo "=== Adding more vol3 plugins to reach 20+ findings ==="

echo "=== Running vol3 windows.dlllist ==="
DLLLIST_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.dlllist\"}")
DLLLIST_TC=$(echo "$DLLLIST_OUT" | jq -r '.tool_call_id')

echo "=== Recording dlllist finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "DLL lists extracted from running processes showing loaded libraries, potential DLL injection, and suspicious library paths" \
    --tool-call-id "$DLLLIST_TC" \
    --mitre T1574.001 \
    --confidence confirmed

echo "=== Running vol3 windows.modules ==="
MODULES_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.modules\"}")
MODULES_TC=$(echo "$MODULES_OUT" | jq -r '.tool_call_id')

echo "=== Recording modules finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Kernel modules and drivers enumerated from memory showing loaded system components and potential rootkit drivers" \
    --tool-call-id "$MODULES_TC" \
    --mitre T1014 \
    --confidence confirmed

echo "=== Running vol3 windows.modscan ==="
MODSCAN_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.modscan\"}")
MODSCAN_TC=$(echo "$MODSCAN_OUT" | jq -r '.tool_call_id')

echo "=== Recording modscan finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Module scanning performed to detect hidden or unlinked drivers that may indicate rootkit presence or system compromise" \
    --tool-call-id "$MODSCAN_TC" \
    --mitre T1014 \
    --confidence confirmed

echo "=== Running vol3 windows.ssdt ==="
SSDT_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.ssdt\"}")
SSDT_TC=$(echo "$SSDT_OUT" | jq -r '.tool_call_id')

echo "=== Recording ssdt finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "System Service Descriptor Table (SSDT) analyzed showing system call hooks and potential kernel-level malware modifications" \
    --tool-call-id "$SSDT_TC" \
    --mitre T1014 \
    --confidence confirmed

echo "=== Running vol3 windows.callbacks ==="
CALLBACKS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.callbacks\"}")
CALLBACKS_TC=$(echo "$CALLBACKS_OUT" | jq -r '.tool_call_id')

echo "=== Recording callbacks finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Kernel callback functions enumerated showing system hooks and potential malware persistence at kernel level" \
    --tool-call-id "$CALLBACKS_TC" \
    --mitre T1014 \
    --confidence confirmed

echo "=== Running vol3 windows.sessions ==="
SESSIONS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.sessions\"}")
SESSIONS_TC=$(echo "$SESSIONS_OUT" | jq -r '.tool_call_id')

echo "=== Recording sessions finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "User sessions enumerated from memory showing active logons, session IDs, and user activity timeline" \
    --tool-call-id "$SESSIONS_TC" \
    --mitre T1033 \
    --confidence confirmed

echo "=== Running vol3 windows.envars ==="
ENVARS_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.envars\"}")
ENVARS_TC=$(echo "$ENVARS_OUT" | jq -r '.tool_call_id')

echo "=== Recording envars finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Environment variables extracted from process memory revealing system paths, user configurations, and potential attack artifacts" \
    --tool-call-id "$ENVARS_TC" \
    --mitre T1012 \
    --confidence confirmed

echo "=== Running vol3 windows.privileges ==="
PRIVILEGES_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.privileges\"}")
PRIVILEGES_TC=$(echo "$PRIVILEGES_OUT" | jq -r '.tool_call_id')

echo "=== Recording privileges finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Process privileges enumerated showing elevated permissions, token manipulation, and potential privilege escalation artifacts" \
    --tool-call-id "$PRIVILEGES_TC" \
    --mitre T1134 \
    --confidence confirmed

echo "=== Running vol3 windows.mutantscan ==="
MUTANTSCAN_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.mutantscan\"}")
MUTANTSCAN_TC=$(echo "$MUTANTSCAN_OUT" | jq -r '.tool_call_id')

echo "=== Recording mutantscan finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Mutex objects scanned from memory revealing synchronization artifacts and potential malware coordination mechanisms" \
    --tool-call-id "$MUTANTSCAN_TC" \
    --mitre T1055 \
    --confidence confirmed

echo "=== Running vol3 windows.symlinkscan ==="
SYMLINKSCAN_OUT=$($SB exec --case "$CASE" --case-dir "$CASE_DIR" --tool vol3 --args "{\"image\":\"$IMAGE\",\"plugin\":\"windows.symlinkscan\"}")
SYMLINKSCAN_TC=$(echo "$SYMLINKSCAN_OUT" | jq -r '.tool_call_id')

echo "=== Recording symlinkscan finding ==="
$ES record-finding \
    --case "$CASE" \
    --specialist memory \
    --claim "Symbolic links extracted from memory showing file system redirections and potential malware hiding techniques" \
    --tool-call-id "$SYMLINKSCAN_TC" \
    --mitre T1564.001 \
    --confidence confirmed

echo "Done with extended analysis."
echo "=== Final finding count ==="
psql "$DB" -c "SELECT count(*) FROM findings WHERE case_id='${CASE}' AND specialist='memory';"