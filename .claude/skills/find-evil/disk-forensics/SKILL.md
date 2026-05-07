# Skill: disk-forensics

## Mission

Perform deep forensic analysis of one or more disk images for a given case.
Extract filesystem artifacts, recover deleted files, build a mactime timeline,
and sweep for IOCs with YARA rules. Record every finding via `./bin/es`
with a valid `tool_call_id` from `./bin/sb`. Do NOT read evidence directly —
all tool access goes through `./bin/sb exec`.

## Inputs

- `CASE_ID` — env var or argument; e.g. `phase15-1778089502`
- `/case/` — evidence root (read-only via broker)
- One or more disk images: `.img`, `.dd`, `.E01`, `.raw`

## Outputs

- ≥10 `findings` rows in Postgres (inserted via `./bin/es record-finding`)
- Optional AGE graph edges (Process/File nodes) via `./bin/es graph`

## Step-by-step Playbook

### Step 0 — Ensure case exists in DB

```bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth -c "
  INSERT INTO cases (case_id, name)
  VALUES ('<CASE_ID>', '<CASE_ID>')
  ON CONFLICT DO NOTHING;
"
```

### Step 1 — Partition map with mmls

Run `mmls` to discover partitions:

```bash
./bin/sb exec --case <CASE_ID> --tool mmls \
  --args '{"image":"/case/disk.img"}'
```

Parse stdout for partition entries. Look for lines like:
```
000:  Meta    0000000000   0000000001   0000000001
001:  -----   0000000000   0000000003   0000000004
002:  NTFS    0000000004   0000000nnnn   ...
003:  FAT16   ...
```

For each data partition found, note the `Start` sector (offset) and type.
Record a finding for the partition map:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist disk \
  --claim "Partition map: <N> partitions found; types: <list>" \
  --tool-call-id <UUID from sb exec output> \
  --confidence confirmed
```

### Step 2 — File listing with fls

For each data partition (use sector offset from Step 1):

```bash
./bin/sb exec --case <CASE_ID> --tool fls \
  --args '{"image":"/case/disk.img","offset":<sector_offset>,"recursive":true}'
```

Parse stdout for interesting entries. Look for:
- Deleted files (lines prefixed with `*` or `d/` with `*`)
- Executable files (`.exe`, `.dll`, `.bat`, `.ps1`, `.vbs`, `.sh`)
- Hidden or suspicious filenames (double extensions, random hex names)
- Files in unusual locations (`/tmp`, `/Recycle.Bin`, `%APPDATA%`, startup paths)

For each suspicious or notable file, record a finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist disk \
  --claim "File found: <path> [deleted=<yes/no>] inode=<inode>" \
  --tool-call-id <UUID> \
  --mitre <MITRE_ID_if_applicable> \
  --confidence inferred
```

Record a summary finding for total file count and deleted file count.

### Step 3 — Recover deleted files with tsk_recover

```bash
./bin/sb exec --case <CASE_ID> --tool tsk_recover \
  --args '{"image":"/case/disk.img","output_dir":"/scratch/recovered","offset":<offset>}'
```

Record a finding for recovered file count if any are found.

### Step 4 — YARA scan

If YARA rules exist in the case or a default ruleset is available, scan the
disk image or recovered files:

```bash
./bin/sb exec --case <CASE_ID> --tool yara \
  --args '{"rules":"/case/rules.yar","target":"/case/disk.img","recursive":false}'
```

If no external rules file is available, create a minimal inline rules file at
`/scratch/minimal.yar` with patterns for common malware strings
(MZ headers, PowerShell encoded commands, base64 blobs, common C2 strings)
and scan with that.

For each YARA match, record a finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist disk \
  --claim "YARA match: rule=<rule_name> at offset=<offset>" \
  --tool-call-id <UUID> \
  --mitre T1027 \
  --confidence inferred
```

### Step 5 — Bulk carving with bulk_extractor

```bash
./bin/sb exec --case <CASE_ID> --tool bulk_extractor \
  --args '{"image":"/case/disk.img","output_dir":"/scratch/bulk_out"}'
```

Parse the output for carved artifacts. Look for:
- `domain.txt` — DNS/domain names → IOC candidates
- `email.txt` — email addresses
- `url.txt` — URLs (look for C2 patterns, encoded payloads)
- `ip.txt` or `ip_histogram.txt` — IP addresses
- `credit_card.txt` — PII
- `base64.txt` — encoded blobs

For each non-empty carved artifact category (more than 0 entries), record a
finding:

```bash
./bin/es record-finding \
  --case <CASE_ID> \
  --specialist disk \
  --claim "bulk_extractor carved <N> <category> artifacts from disk image" \
  --tool-call-id <UUID> \
  --confidence inferred
```

For high-value individual artifacts (suspicious URLs, IPs, domains), record
additional findings with `--mitre` tags where applicable.

### Step 6 — Timeline with log2timeline + psort (optional)

If the image contains a supported filesystem, build a mactime timeline:

```bash
./bin/sb exec --case <CASE_ID> --tool log2timeline \
  --args '{"image":"/case/disk.img","output_file":"/scratch/timeline.plaso"}'
```

Then filter and sort:

```bash
./bin/sb exec --case <CASE_ID> --tool psort \
  --args '{"input":"/scratch/timeline.plaso","output_file":"/scratch/timeline.csv"}'
```

Look for anomalies: files modified in suspicious date ranges, files with
timestamps far out of baseline range. Record findings for any anomalies
discovered.

### Step 7 — icat for suspicious inodes (targeted extraction)

For any high-interest inode discovered in Steps 2–3, extract the file content:

```bash
./bin/sb exec --case <CASE_ID> --tool icat \
  --args '{"image":"/case/disk.img","inode":<inode>,"offset":<offset>}'
```

Record a finding for any extracted file whose content is suspicious.

## Minimum findings target

You MUST produce at least 10 `findings` rows before exiting. Each finding must
have:
- A non-empty `claim` describing what was found
- A `tool_call_id` from an actual `./bin/sb exec` call
- A `specialist` value of `disk`

If you reach Step 5 and still have fewer than 10 findings, create additional
specific findings from bulk_extractor output detail (individual domains, IPs,
URLs each as separate findings).

## Error handling

- If a tool call returns exit code != 0, log the stderr from the response JSON
  and continue to the next step. Do NOT stop the investigation.
- If `./bin/sb exec` itself fails (network error, broker down), retry once. If
  it fails again, record a finding noting the tool failure and continue.
- Never modify evidence files. Evidence is under `/case/` (read-only); outputs go to `/scratch/`.

## Constraints

- MUST use `./bin/sb exec` for every forensics tool call.
- MUST use `./bin/es record-finding` for every finding.
- MUST NOT run `mmls`, `fls`, `yara`, or any other forensics binary directly.
- MUST NOT write files to `/case/` (read-only). Write outputs to `/scratch/`.
- MUST exit 0 when ≥10 findings have been recorded; exit 1 only on fatal error
  (e.g. image not found, DB unreachable).

## Tool budget

Budget: 20 broker calls per image. Priority order:
1. mmls (1 call)
2. fls (1 call per partition, max 3)
3. tsk_recover (1 call)
4. bulk_extractor (1 call)
5. yara (1 call)
6. log2timeline + psort (2 calls, skip if budget < 5 remaining)
7. icat (up to 3 calls for top suspects)
