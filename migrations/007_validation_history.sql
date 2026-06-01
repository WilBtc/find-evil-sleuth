-- find-evil-sleuth · append-only validation history (Phase 3.1.6)
-- Replaces the destructive UPDATE-reset pattern in 004_pg_cron_revalidation.sql
-- with an immutable audit trail.
--
-- Changes:
--   1. Create validation_history table (append-only, never updated).
--   2. Drop the destructive 'revalidate-stale-findings' pg_cron job that was
--      resetting confirmed findings back to 'pending' every 30 minutes.
--   3. Re-create a safe pg_cron job that only enqueues truly pending findings
--      and schedules confirmed findings for re-validation (NOT reset) when their
--      latest history row is >24 h old.

-- ── 1. Create validation_history ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS validation_history (
    history_id              bigserial PRIMARY KEY,
    finding_id              text        NOT NULL REFERENCES findings(finding_id),
    status                  text        NOT NULL
                                        CHECK (status IN ('confirmed','refuted','inconclusive','drift','pending')),
    validated_at            timestamptz NOT NULL DEFAULT now(),
    validation_tool_call_id uuid
);

CREATE INDEX IF NOT EXISTS ix_valh_finding_id   ON validation_history (finding_id);
CREATE INDEX IF NOT EXISTS ix_valh_validated_at ON validation_history (finding_id, validated_at DESC);

-- ── 2. Drop the old destructive pg_cron job ──────────────────────────────────

DO $outer$ BEGIN
    PERFORM cron.unschedule(jobid)
    FROM    cron.job
    WHERE   jobname = 'revalidate-stale-findings';
EXCEPTION WHEN undefined_table OR undefined_function THEN NULL;
END $outer$;

-- ── 3. Re-create pg_cron job (append-only, no destructive reset) ─────────────
--
-- Strategy:
--   a) For findings that are still 'pending' and have never been validated:
--      do nothing — they are already enqueued for the next validator run.
--   b) For 'confirmed' findings whose LATEST history row is >24 h old:
--      insert a new 'pending' history row to signal re-validation is due,
--      then set findings.validation_status = 'pending' so the validator
--      picks them up.  The existing confirmed history row is NOT deleted.
--
-- The pg_cron schedule: every 30 minutes (same as before).

-- cron.schedule for 'revalidate-stale-confirmed-findings' removed: superseded by
-- 018 — per-finding revalidation. The */30 time-based job is no longer recreated
-- on a fresh sequential apply, preventing the revalidation storm. The
-- validation_history table/indexes above and the cron.unschedule block (which
-- tears down any old job from a prior deploy) are retained. No-op.
