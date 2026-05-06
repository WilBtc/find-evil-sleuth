# Skill: findings-validator

## Mission

Re-execute the original tool call for each finding in a given case and
specialist scope, then set `validation_status` to one of:

- **confirmed** — re-run exit_code matches original AND claim is consistent
  with new stdout.
- **refuted** — re-run produces output that directly contradicts the claim.
- **inconclusive** — re-run exits non-zero or evidence is no longer accessible,
  making confirmation impossible.
- **drift** — exit_code matches but stdout hash differs materially (e.g.,
  timestamp-only change); claim still valid but data has evolved.

## Inputs

- `CASE_ID` — env var or argument; e.g. `phase15-1778089502`
- `SPECIALIST` — optional filter; e.g. `disk`, `memory`, `network`
  (if omitted, validate all findings for the case)

## Outputs

- `findings.validation_status` updated for every targeted finding
- `findings.last_validated_at` updated to `now()`
- `tool_calls.is_validation = true` set on every re-execution call

## Step-by-step Playbook

### Step 0 — Enumerate findings to validate

Query the database for all findings with `validation_status = 'pending'`
for the given case (and specialist if provided):

```bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth \
  -f scripts/validator-query.sql
```

Or use the inline pattern: write the query to a temp file and run it.

The result set has columns:
`finding_id | tool_call_id | tool | args | exit_code | claim | confidence`

### Step 1 — Re-execute each tool call

For each finding in the result set, re-run the original broker call:

```bash
./bin/sb exec --case <CASE_ID> --tool <tool> --args '<args_json>'
```

Capture the JSON response:
```json
{
  "tool_call_id": "<new-uuid>",
  "artifact_hash": "blake3:...",
  "exit_code": 0,
  "duration_ms": 1234,
  "stdout": "...",
  "stderr": "..."
}
```

### Step 2 — Determine validation status

Apply these rules in order:

1. If `sb exec` itself fails (broker down, podman error): mark **inconclusive**,
   do NOT retry automatically — leave for the pg_cron revalidation job.

2. If new `exit_code != 0` AND original `exit_code == 0`:
   - If stderr contains "no such file" or "not found": **inconclusive**
     (evidence no longer present)
   - Otherwise: **refuted** (tool now fails where it previously succeeded)

3. If new `exit_code == 0` AND original `exit_code == 0`:
   - Check whether the claim is consistent with the new `stdout`:
     - If stdout contains the key artifact the claim references: **confirmed**
     - If stdout is materially different but claim could still be valid
       (e.g., timestamps shifted): **drift**
     - If stdout explicitly contradicts the claim: **refuted**

4. If both original and new `exit_code != 0`:
   - The original finding documents a tool failure; the tool still fails:
     **confirmed** (the failure itself is the finding)

5. If new `exit_code == 0` AND original `exit_code != 0`:
   - Tool now succeeds where it previously failed: **inconclusive**
     (claim may need to be re-evaluated by a specialist)

### Step 3 — Record the validation

```bash
./bin/es set-validation \
  --finding-id <FINDING_ID> \
  --status <confirmed|refuted|inconclusive|drift> \
  --validation-tool-call-id <new-tool-call-id>
```

If the re-execution was skipped (broker down), omit `--validation-tool-call-id`.

### Step 4 — Verify completion

After processing all findings, verify 100% are no longer `pending`:

```bash
psql postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth \
  -f scripts/validator-status.sql
```

Expected output: zero rows with `validation_status = 'pending'` for the case.

## Claim-consistency heuristics

| Tool | Claim key phrase | Look for in new stdout |
|---|---|---|
| mmls | "N partitions" | Same partition count line |
| fls | "N entries" / "MBR FAT1 FAT2" | Same metadata entry names |
| tsk_recover | "N deleted files recovered" | Same count in stdout |
| icat | "FAT16 / MBR / FAT1" | Same filesystem signature bytes |
| bulk_extractor | "tool not found" | Non-zero exit or same error |
| log2timeline | "failed" / "cannot write" | Same error in stderr |
| vol3 | plugin name + row count | Same rows ± 5% |
| tshark | packet count / protocol | Same stats ± 10 packets |
| zeek | "connections" count | Same file list |
| yara | "N matches" | Same match count |

## Decision matrix quick reference

| orig exit | new exit | stdout match | status |
|-----------|----------|--------------|--------|
| 0 | 0 | yes | confirmed |
| 0 | 0 | no (drift) | drift |
| 0 | 0 | contradicts | refuted |
| 0 | !=0 | missing evidence | inconclusive |
| 0 | !=0 | other error | refuted |
| !=0 | !=0 | same failure | confirmed |
| !=0 | 0 | — | inconclusive |
| broker down | — | — | inconclusive |

## Minimum coverage target

100% of targeted findings MUST receive a non-`pending` status before the
validator exits 0. If any remain `pending`, exit 1.

## Error handling

- Tool re-execution may fail for environmental reasons (missing image, broker
  restart). Mark those **inconclusive** — do NOT mark them **refuted**.
- If Postgres is unreachable, exit 1 immediately.
- Each finding is independent; a failure on one does not stop others.

## Constraints

- MUST use `./bin/sb exec` for every tool re-execution.
- MUST use `./bin/es set-validation` to update each finding.
- MUST NOT directly UPDATE the findings table.
- MUST NOT mark a finding `refuted` solely because the tool call was slow or
  timed out — use `inconclusive` for timeouts.
- Exit 0 only when all targeted findings have been validated.
