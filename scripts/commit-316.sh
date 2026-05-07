#!/usr/bin/env bash
set -euo pipefail
git commit -F - <<'MSGEOF'
fix(3.1.6): append-only validation_history replaces destructive pg_cron reset

- migrations/007_validation_history.sql: creates validation_history table,
  drops old destructive revalidate-stale-findings job, installs safe
  replacement job that only enqueues confirmed findings with history >24h old
- evidence-store/src/findings.rs: set_validation now INSERTs history row in
  same transaction as findings UPDATE; full audit trail preserved
- narrator skill + agent: LATERAL join resolves status from latest history row
- scripts/build-es-local.sh: cargo build helper for evidence-store binary
- Acceptance: 11 confirmed findings survive cron job run (UPDATE 0), 11 rows
  appended to validation_history

Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
MSGEOF
