# Skill: ir-narrator

## Mission

Query all confirmed (and drift) findings for a given case from Postgres, build a
structured MITRE ATT&CK-aligned Markdown incident report, and write it to
`cases/<CASE_ID>/report.md`. Every factual claim in the report body MUST be
followed immediately by one or more `[F-NNN]` citations referencing the finding
row that supports it. The citation hook checks this before the agent exits.

## Inputs

- `CASE_ID` — env var or argument; e.g. `phase15-1778089502`
- Postgres findings table: columns `finding_id`, `specialist`, `claim`,
  `validation_status`, `mitre_technique`, `confidence`

## Outputs

- `cases/<CASE_ID>/report.md` — structured Markdown with `[F-NNN]` cites
- Exit code 0 when citations pass the hook; 1 on any failure

## Report Structure

```
# Incident Report — <CASE_ID>

**Generated:** <ISO8601>
**Case:** <CASE_ID>
**Findings:** <N> confirmed

---

## Executive Summary

<2–3 sentence summary of the investigation. Every factual sentence
must end with [F-NNN] or a list of cites like [F-003][F-007].>

---

## Findings by Specialist

### Disk Forensics

<One paragraph or bullet per finding, each ending with [F-NNN].>

### Memory Forensics

<Same pattern; omit section if no memory findings.>

### Network Forensics

<Same pattern; omit section if no network findings.>

---

## MITRE ATT&CK Techniques Observed

| Technique | ID | Finding |
|---|---|---|
| <name> | <T-ID> | [F-NNN] |

---

## Indicators of Compromise

| Type | Value | Finding |
|---|---|---|
| <type> | <value> | [F-NNN] |

---

## Conclusion

<Summary paragraph with [F-NNN] cites.>

---

## Appendix — Finding Index

| ID | Specialist | Validation | Claim |
|---|---|---|---|
| F-001 | disk | confirmed | <claim> |
```

## Citation Format Rules

1. A `[F-NNN]` tag must appear after EVERY sentence that asserts a forensic fact.
2. `NNN` must match an actual `finding_id` in the database (e.g., `F-003`, `F-014`).
3. Multiple cites on one sentence: `[F-003][F-007][F-013]` with no space between them.
4. Table rows that reference a finding use the `[F-NNN]` form in the Finding column.
5. Section headers, the appendix table itself, generated timestamps, and the
   report metadata block are exempt from the citation requirement.

## Step-by-step Playbook

### Step 0 — Ensure case directory exists

```bash
mkdir -p cases/<CASE_ID>
```

### Step 1 — Fetch confirmed findings

Write the query to a temp file and run it.

The query resolves the authoritative status from `validation_history` when
a history row is present (latest row wins); otherwise it falls back to
`findings.validation_status`.  This avoids the narrator seeing stale status
from a destructive reset.

```sql
SELECT f.finding_id,
       f.specialist,
       f.claim,
       COALESCE(vh_latest.status, f.validation_status) AS validation_status,
       f.mitre_technique,
       f.confidence
FROM   findings f
LEFT JOIN LATERAL (
    SELECT status
    FROM   validation_history vh
    WHERE  vh.finding_id = f.finding_id
    ORDER  BY vh.validated_at DESC
    LIMIT  1
) vh_latest ON true
WHERE  f.case_id = '<CASE_ID>'
  AND  COALESCE(vh_latest.status, f.validation_status) IN ('confirmed', 'drift')
ORDER BY f.specialist, f.finding_id;
```

```bash
psql "${PG_RO_URL:-postgresql://sleuth_ro_user:changeme-ro-dev-only@127.0.0.1:5532/sleuth}" \
  -f /tmp/narrator_<CASE_ID>.sql 2>&1
```

Parse the output into a structured list. Each row is one finding to cite.

If there are zero confirmed findings, write a minimal report noting no confirmed
findings and exit 0 (report still passes the citation check — no claims to cite).

### Step 2 — Fetch case metadata (optional)

```
SELECT * FROM cases WHERE case_id = '<CASE_ID>';
```

Use the case name and created_at for report metadata.

### Step 3 — Compose the report

Build the Markdown in memory following the Report Structure above. Rules:
- Group findings by specialist: `disk` → `memory` → `network`.
- For each finding, write one bullet or sentence ending with `[<finding_id>]`.
- Derive the MITRE table from findings where `mitre_technique IS NOT NULL`.
- IOCs section: extract notable artifacts (IPs, domains, file hashes) from
  claims where applicable.
- Conclusion: 2–3 sentences summarising the investigation outcome with cites.

### Step 4 — Write the report file

```bash
cat > cases/<CASE_ID>/report.md << 'REPORT_EOF'
<full report content>
REPORT_EOF
```

Or use a series of `echo`/`printf` commands piped to the file.

### Step 5 — Verify citations pass the hook

Run the citation checker before exiting:

```bash
bash scripts/check-report-citations.sh cases/<CASE_ID>/report.md
```

The script exits 0 if every factual paragraph has at least one `[F-NNN]` cite;
exits 1 with a list of offending paragraphs if not.

If the check fails:
1. Re-read the report.
2. Add missing `[F-NNN]` tags to uncited sentences.
3. Rewrite the file.
4. Re-run the check.

Exit 0 only when the citation check passes.

## Citation check rules (enforced by scripts/check-report-citations.sh)

The checker scans each non-blank, non-header, non-table, non-code-block line
of the report. A "claim line" is any line that:
- Contains an alphabetic word AND
- Is not a heading (`#`), horizontal rule (`---`), table row (`|`),
  code fence (`` ` ``), or metadata key-value line (`**Key:**`)

For each claim line, the checker asserts that `[F-` appears somewhere on the
line. If the line lacks a citation, it is flagged as an error.

## Error handling

- If the psql query fails, exit 1 immediately (no report to write).
- If the report file cannot be written, exit 1.
- If the citation check fails, fix the report rather than exiting 1.
- Never make up finding IDs. Only cite IDs returned by the database query.

## Constraints

- MUST NOT run any forensics tools — this agent is read-only.
- MUST use `psql` (via SQL files) to query findings — never `./bin/sb exec`.
- MUST write the report to `cases/<CASE_ID>/report.md`.
- MUST pass `scripts/check-report-citations.sh` before exiting 0.
- MUST NOT cite a finding that has `validation_status = 'pending'` or `'refuted'`.
- MUST include every confirmed finding in the Appendix — Finding Index table.
