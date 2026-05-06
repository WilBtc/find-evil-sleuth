# Skill: memory-forensics

## Mission

Perform deep forensic analysis of a Windows memory image for a given case using
Volatility 3 (`vol3`). Extract process tree, injected code, network connections,
services, and registry persistence. Record every finding via `./bin/es` with a
valid `tool_call_id` from `./bin/sb`. Do NOT read evidence directly — all tool
access goes through `./bin/sb exec`.

## Inputs

- `CASE_ID` — env var or argument; e.g. `phase15-mem-001`
- `/case/<CASE_ID>/` — evidence root (read-only via broker)
- One memory image: `.mem`, `.raw`, `.vmem`, `.dmp`

## Outputs

- ≥10 `findings` rows in Postgres (inserted via `./bin/es record-finding`)
- Optional AGE graph edges (Process/NetworkEndpoint nodes) via `./bin/es graph`

## Step-by-step Playbook

### Step 0 — Ensure case exists in DB

```bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth -c "
  INSERT INTO cases (case_id, name)
  VALUES ('<CASE_ID>', '<CASE_ID>')
  ON CONFLICT DO NOTHING;
"
```

### Step 1 — OS profile / image info with windows.info

Run `windows.info` to identify the memory image and OS build:

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.info"}'
```

Parse stdout for `NtBuildLab`, `NtProductType`, `NtMajorVersion`, kernel base,
and DTB. Record a finding with these details:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist memory \
  --claim "Memory image: OS=<OS_version> build=<build_str> kernel_base=<addr> DTB=<addr>" \
  --tool-call-id <UUID from sb exec output> \
  --confidence confirmed
```

If `windows.info` exits non-zero (profile mismatch), store profile in
`case_plan.config.os_profile` and retry the step — see Self-Correction below.

### Step 2 — Process list with windows.pslist

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.pslist"}'
```

Parse stdout for process entries. Look for:
- Orphaned processes (PPID does not match any live PID)
- Processes with unusual names (random hex, misspelled system names)
- Duplicate process names with different PIDs
- System process in unusual locations
- `cmd.exe`, `powershell.exe`, `wscript.exe`, `mshta.exe` children of non-shell parents

Record a summary finding with total process count and any suspicious entries:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist memory \
  --claim "Process list: <N> processes; suspicious: <list of suspicious pids/names>" \
  --tool-call-id <UUID> \
  --mitre T1055 \
  --confidence inferred
```

For each suspicious process found, record an additional individual finding.

### Step 3 — Process tree with windows.pstree

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.pstree"}'
```

Parse stdout for parent-child anomalies:
- `svchost.exe` not parented by `services.exe`
- `explorer.exe` spawning `cmd.exe` or `powershell.exe`
- `lsass.exe` or `csrss.exe` spawning child processes
- Any process tree depth > 5 levels with non-browser executables

Record a finding for each anomalous parent-child relationship found.

### Step 4 — Command lines with windows.cmdline

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.cmdline"}'
```

Parse stdout for suspicious command lines. Look for:
- Base64-encoded strings (`-EncodedCommand`, `[Convert]::From`)
- Powershell download cradles (`DownloadString`, `IEX`, `Invoke-Expression`)
- `cmd /c` one-liners with obfuscation characters (`^`, `,`, `;`)
- References to `%TEMP%`, `%APPDATA%`, or `C:\Users\*\AppData\Roaming`
- Long command lines with concatenated strings

For each suspicious command line, record a finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist memory \
  --claim "Suspicious cmdline PID=<pid> name=<name>: <excerpt>" \
  --tool-call-id <UUID> \
  --mitre T1059.001 \
  --confidence inferred
```

### Step 5 — Injected code detection with windows.malfind

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.malfind"}'
```

Parse stdout for regions with:
- `PAGE_EXECUTE_READWRITE` (RWX) permissions
- MZ header present in non-image-backed memory
- High entropy regions in heap/stack space

For each suspicious VAD region, record a finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist memory \
  --claim "Injected code: PID=<pid> name=<name> VA=<addr> permissions=RWX header=<MZ|shellcode>" \
  --tool-call-id <UUID> \
  --mitre T1055 \
  --confidence inferred
```

If windows.malfind returns many results (> 20), record first 5 individually and
summarize the rest in one finding.

### Step 6 — Network connections with windows.netscan

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.netscan"}'
```

Parse stdout for active and closed connections. Look for:
- Connections to non-local IP ranges (not RFC1918/loopback) from non-browser processes
- Listening ports on unusual port numbers (not 80, 443, 445, 135, 3389)
- Connections from `svchost.exe` with unusual foreign IPs
- UDP beacon patterns (multiple short-duration connections to same IP)

For each suspicious connection or network IOC, record a finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist memory \
  --claim "Network connection: PID=<pid> name=<name> state=<state> local=<ip:port> foreign=<ip:port>" \
  --tool-call-id <UUID> \
  --mitre T1071 \
  --confidence inferred
```

### Step 7 — Service scan with windows.svcscan

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.svcscan"}'
```

Parse stdout for:
- Services with random-looking names or descriptions
- Services running from `%TEMP%`, `%APPDATA%`, or non-standard paths
- Services with no associated DLL or binary (ghost services)
- Newly created services (recent `ServiceName` creation time)

For each suspicious service, record a finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist memory \
  --claim "Suspicious service: name=<svc> state=<state> binary=<path>" \
  --tool-call-id <UUID> \
  --mitre T1543.003 \
  --confidence inferred
```

### Step 8 — Registry persistence with windows.registry.printkey

Check known persistence locations. Run the plugin for each key:

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.registry.printkey","extra_args":["--key","Software\\Microsoft\\Windows\\CurrentVersion\\Run"]}'

./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.registry.printkey","extra_args":["--key","Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce"]}'

./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.registry.printkey","extra_args":["--key","SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options"]}'
```

For each value present in `Run` / `RunOnce` keys, record a finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist memory \
  --claim "Registry persistence: key=<key_path> value=<name> data=<data>" \
  --tool-call-id <UUID> \
  --mitre T1547.001 \
  --confidence confirmed
```

For IFEO debugger entries (potential process injection mechanism), use T1546.012.

### Step 9 — DLL list for top suspect processes (windows.dlllist)

For any process flagged in Steps 2–5, check its loaded DLLs:

```bash
./bin/sb exec --case <CASE_ID> --tool vol3 \
  --args '{"image":"/case/<CASE_ID>/memory.mem","plugin":"windows.dlllist","pid":<pid>}'
```

Look for:
- DLLs loaded from `%TEMP%` or `%APPDATA%`
- DLLs with no path (injected in-memory)
- Known-bad DLL names (common red-team DLLs)
- DLLs with suspicious paths relative to other loaded modules

Record a finding for each suspicious DLL:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist memory \
  --claim "Suspicious DLL: PID=<pid> name=<proc> dll=<dll_path> base=<addr>" \
  --tool-call-id <UUID> \
  --mitre T1574.001 \
  --confidence inferred
```

## Self-Correction Protocol

If `windows.malfind` or any plugin exits non-zero with a profile mismatch:

1. Re-run `windows.info` to get the correct profile.
2. Update the case note: record a finding noting the correction.
3. Re-run the failed plugin.

This is the hot path for Phase 4's self-correction demo (plan 06).

## Minimum findings target

You MUST produce at least 10 `findings` rows before exiting. Each finding must
have:
- A non-empty `claim` describing what was found
- A `tool_call_id` from an actual `./bin/sb exec` call
- A `specialist` value of `memory`

If you reach Step 7 with fewer than 10 findings, run `windows.dlllist` on the
top 3 most suspicious PIDs from Steps 2–5 and record individual DLL findings.

If the memory image has no suspicious activity at all (all plugins return
clean results), record one "no evidence" finding per plugin (confirmed clean)
to meet the 10-finding minimum.

## Error handling

- If a tool call returns exit code != 0, log the `stderr` field from the JSON
  response and continue to the next step. Do NOT stop the investigation.
- If `./bin/sb exec` itself fails (broker down), retry once. If it fails again,
  record a finding noting the tool failure and continue.
- Do NOT modify evidence files. All tool outputs go to `/scratch` inside the
  container (managed by broker).

## Constraints

- MUST use `./bin/sb exec` for every vol3 plugin call.
- MUST use `./bin/es record-finding` for every finding.
- MUST NOT run `vol` or any other forensics binary directly in bash.
- MUST NOT write files outside `/case/<CASE_ID>/` (broker enforces this).
- MUST exit 0 when ≥10 findings have been recorded; exit 1 only on fatal error
  (e.g. memory image not found, DB unreachable).

## Tool budget

Budget: 15 broker calls per image. Priority order:
1. windows.info (1 call)
2. windows.pslist (1 call)
3. windows.pstree (1 call)
4. windows.cmdline (1 call)
5. windows.malfind (1 call)
6. windows.netscan (1 call)
7. windows.svcscan (1 call)
8. windows.registry.printkey Run (1 call)
9. windows.registry.printkey RunOnce (1 call)
10. windows.dlllist for top suspect PIDs (up to 3 calls)

## MITRE ATT&CK quick reference

| Observation | MITRE ID |
|---|---|
| Process injection / injected region | T1055 |
| Encoded PowerShell command | T1059.001 |
| Suspicious service created | T1543.003 |
| Registry Run/RunOnce persistence | T1547.001 |
| IFEO debugger entry | T1546.012 |
| Suspicious DLL loaded | T1574.001 |
| Network C2 connection | T1071 |
| DLL search order hijacking | T1574.002 |
| Credential access from lsass | T1003.001 |
