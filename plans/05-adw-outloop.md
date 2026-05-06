# 05 · ADW Outloop (`adws/investigate.py`)

> The driver. Subprocesses `claude --print` per agent, polls Postgres for state, decides next move. Reuses the existing `~/.local/bin/adw` Rust harness for scheduling/dashboards.

## State machine

```
INIT → TRIAGE → DISPATCH → SPECIALISTS_RUNNING ─┬─→ VALIDATING ─┬─→ NARRATING → JUDGED → DONE
                                                 │               │
                                                 │               └─→ SELF_CORRECTING → SPECIALISTS_RUNNING
                                                 │
                                                 └─→ SELF_CORRECTING (specialist failure)
```

Stored in `cases.status` + ephemeral process state. Resumable: re-running `investigate.py` on an existing case_id picks up from `cases.status`.

## States

### INIT
Create `cases` row. Reserve ports via `port-registry`. Verify postgres reachable, broker self-test (`./bin/sb describe vol3`), evidence-store self-test (`./bin/es init`).

### TRIAGE
`claude --print --agent triage --case <id>`. Block until `case_plan` populated. Hard timeout 5 min.

### DISPATCH
Read `case_plan`. For each specialist row, schedule a `claude --print --agent <specialist>` subprocess. Cap parallelism = `min(specialists, 3)`.

### SPECIALISTS_RUNNING
Poll `tool_calls` and `findings` rows tagged with the case. Wait for all subprocesses to exit OR per-specialist timeout (45 min). On timeout: capture stderr, write to `self_corrections`, transition to SELF_CORRECTING.

### VALIDATING
For every `findings.validation_status='pending'`, enqueue (already done by pg_cron). Spawn `claude --print --agent validator` once and let it drain queue. Cap 30 min.

### SELF_CORRECTING
Read most recent `self_corrections` row without `succeeded`. Build retry prompt:
```
Previous attempt:
  Tool: <failed_tool>
  Args: <failed_args>
  Exit: <failed_exit>
  Stderr tail: <stderr_tail>

Allowed strategies for this failure mode: <strategy_hints>

Choose the next attempt and emit the broker invocation.
```
Subprocess Sonnet 4.6, parses single JSON, runs broker, records `succeeded=true|false`. Cap 3 attempts per finding.

### NARRATING
Spawn 3 narrator subprocesses in parallel (best-of-N). Each writes to `report-candidate-N.md`.

### JUDGED
Spawn judge subprocess Opus 4.7 with the 3 candidates + finding pool. Picks one. Move to `report.md`. Commit to `case/<id>` git branch.

### DONE
Set `cases.finished_at`, status `complete`. `./bin/es export --case <id> --to submission/` for the execution log artifact.

## Idempotency

Every subagent step is keyed by `(case_id, agent, step_seq)`. Re-running the driver replays only missing steps. Critical for survive-a-crash during the recording.

## Parallelism caps

- Specialists: 3
- Validator: 1 process (queue worker pattern)
- Narrator candidates: 3
- Per-tool-call concurrency: enforced inside broker

## Cost guardrails

`obs` cost guardian (existing Safety Layer probe) checks tokens spent per case. Hard cap $20/case dev, $30/case for the demo run. On breach: pause, alert, await manual continue.

## Failure handling

- Subprocess crash → capture stderr, persist `self_corrections` row with `retry_strategy='subprocess_restart'`, retry once.
- DB unavailable → exponential backoff 5/15/45s, then alert and exit 1.
- Broker permanent error (allowlist miss) → halt the offending agent, mark case `failed`, surface clear message in obs.

## Hooks integration

PostToolUse hook posts to `agent-obs:8910/event`. Stop hook (in narrator only) validates citations; if violated, raises a non-zero exit which ADW interprets as best-of-N candidate disqualified.

## Observability dashboard

`adw dashboard` (existing CLI) ASCII view. Add: cases pane (status, runtime, findings count, validation %, self-corrections), tool_calls last 10 (with exit code coloring), AGE stats (nodes/edges).
