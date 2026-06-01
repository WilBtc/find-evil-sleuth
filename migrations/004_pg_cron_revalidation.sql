-- find-evil-sleuth · pg_cron re-validation job (Phase 2.3.3)
-- Schedules a job that every 30 minutes enqueues:
--   (a) findings with validation_status = 'pending'
--   (b) findings not validated in the last hour (stale validated/inconclusive rows)
-- "Enqueue" means resetting validation_status → 'pending' so the
-- findings-validator agent will pick them up on its next run.
-- Idempotent: removes any existing same-named job before re-creating.

DO $outer$ BEGIN
    -- Remove existing job by name (select jobid first; no-op when absent)
    PERFORM cron.unschedule(jobid)
    FROM    cron.job
    WHERE   jobname = 'revalidate-stale-findings';
EXCEPTION WHEN undefined_table OR undefined_function THEN NULL;
END $outer$;

-- cron.schedule for 'revalidate-stale-findings' removed: superseded by 018 —
-- per-finding revalidation. The destructive */30 UPDATE-reset storm is no longer
-- recreated on a fresh sequential apply. The cron.unschedule block above is kept
-- so any pre-existing job from an older deploy is torn down. No-op.
