# Skill: dfir-triage

## Mission

Walk the case directory, classify every evidence file by type, and write one
`case_plan` row per specialist needed. Emit a JSON dispatch that the ADW driver
consumes to fan-out specialists in parallel. You never perform analysis yourself.

## Inputs

- `CASE_ID` — env var or first argument; the case identifier (e.g. `phase15-1778089502`)
- `/case/<CASE_ID>/` — evidence root, mounted read-only by the broker

## Outputs

- One `case_plan` row per specialist inserted into Postgres (via `./bin/es` in future; for now via psql)
- JSON dispatch printed to stdout:
  ```json
  {
    "case_id": "<id>",
    "specialists": ["disk", "memory", "network"],
    "config": {
      "disk":    { "images": ["disk.img"], "tool_budget": 20 },
      "memory":  { "images": ["memory.mem"], "tool_budget": 15 },
      "network": { "images": ["traffic.pcap"], "tool_budget": 15 }
    }
  }
  ```

## Step-by-step Playbook

### Step 1 — Enumerate evidence files

```bash
ls -la cases/<CASE_ID>/
```

For each file found, record its name, size, and extension.

### Step 2 — Classify by magic bytes and extension

Run `./bin/sb exec --case <id> --tool file --args '{"path":"<file>"}'` for
each evidence file. Wait for the JSON response; extract the `stdout` field.

Classification rules (applied in order; first match wins):

| Output pattern | Specialist |
|---|---|
| `MBR` / `partition table` / `DOS/MBR boot sector` | `disk` |
| extension `.E01`, `.dd`, `.img`, `.raw` + `data` | `disk` |
| `Windows Event Log` / `.evtx` | `disk` (log) |
| extension `.mem`, `.vmem`, `.dmp` | `memory` |
| `data` + extension `.mem` or `.vmem` | `memory` |
| `pcap` / `pcapng` / `tcpdump` | `network` |
| extension `.pcap`, `.pcapng`, `.cap` | `network` |
| `.log`, `.txt`, `.csv` | `disk` (log, folded) |

If a file matches no rule, classify as `disk` (default) and note uncertainty.

### Step 3 — Compute BLAKE3 hash for each file

```bash
./bin/sb exec --case <id> --tool blake3 --args '{"path":"<file>"}'
```

Store the hash in the dispatch JSON under `config.<specialist>.evidence_hashes`.

> Note: if `blake3` is not in the tool spec, use `sha256sum` via the broker's
> `file` tool, or record `null` and continue.

### Step 4 — Write case_plan rows

For each specialist identified, insert a `case_plan` row. Until `./bin/es`
gains a `plan` subcommand, write directly via psql:

```bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth -c "
  INSERT INTO case_plan (case_id, specialist, config)
  VALUES ('<case_id>', '<specialist>', '<config_json>'::jsonb)
  ON CONFLICT (case_id, specialist) DO UPDATE SET config = EXCLUDED.config;
"
```

Where `config_json` contains:
```json
{
  "images": ["<filename>"],
  "tool_budget": 20,
  "evidence_hashes": { "<filename>": "<hash>" },
  "classified_by": "dfir-triage",
  "classified_at": "<iso8601>"
}
```

### Step 5 — Emit dispatch JSON

Print the dispatch JSON to stdout (captured by ADW driver):

```json
{
  "case_id": "<id>",
  "specialists": ["disk", "memory", "network"],
  "config": { ... }
}
```

## Error handling

- If `./bin/sb exec` fails for a file, log to stderr and continue with the
  remaining files. A failed hash does not block classification.
- If the case directory is empty, print `{"case_id":"…","specialists":[],"error":"no evidence found"}` and exit 1.
- If psql INSERT fails, print the error to stderr and exit 1 (do not emit dispatch — the ADW driver must not proceed with a partial plan).

## Constraints

- You MUST use `./bin/sb exec` for file inspection — never invoke `file` or `sha256sum` directly.
- You MUST use `./bin/es` or `psql` for DB writes — never write files outside the workspace.
- You MUST NOT perform any forensic analysis; classification only.
- You MUST exit with code 0 on success, non-zero on any unrecoverable error.

## Tool budget

Triage is cheap: `file` + optional hash = 2 broker calls per evidence file.
Maximum 3 retries per file if the broker returns a transient error.
