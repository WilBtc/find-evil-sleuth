-- find-evil-sleuth · per-finding event-driven (re)validation (Phase 4.x)
-- Replaces the TIME-BASED pg_cron re-validation (mig 004 / 007) with PER-FINDING,
-- event-driven validation.
--
-- Rationale: case evidence is immutable (a static disk image / pcap). Re-running the
-- same tool on the same bytes 24 h later yields identical output, so wall-clock
-- re-validation is wasted work and the wrong trigger. Validation must be CAUSED by a
-- finding event: (a) the finding is created, or (b) an explicit per-finding
-- re-validation request when its source evidence is known to have changed (drift).
-- No clock, no human input.

-- ── 1. Remove ALL time-based re-validation cron jobs ─────────────────────────
DO $o$ BEGIN
    PERFORM cron.unschedule(jobid)
    FROM    cron.job
    WHERE   jobname IN ('revalidate-stale-findings','revalidate-stale-confirmed-findings');
EXCEPTION WHEN undefined_table OR undefined_function THEN NULL;
END $o$;

-- ── 2. Per-finding enqueue trigger ───────────────────────────────────────────
-- Fires when a finding is created, or when its status is (re)set to 'pending' by an
-- event. Writes an append-only audit row and signals the validator via NOTIFY.
CREATE OR REPLACE FUNCTION enqueue_finding_validation() RETURNS trigger AS $fn$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO validation_history (finding_id, status) VALUES (NEW.finding_id, 'pending');
        PERFORM pg_notify('finding_validate', NEW.finding_id);
    ELSIF (TG_OP = 'UPDATE'
           AND NEW.validation_status = 'pending'
           AND OLD.validation_status IS DISTINCT FROM 'pending') THEN
        INSERT INTO validation_history (finding_id, status) VALUES (NEW.finding_id, 'pending');
        PERFORM pg_notify('finding_validate', NEW.finding_id);
    END IF;
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enqueue_finding_validation ON findings;
CREATE TRIGGER trg_enqueue_finding_validation
    AFTER INSERT OR UPDATE OF validation_status ON findings
    FOR EACH ROW EXECUTE FUNCTION enqueue_finding_validation();

-- ── 3. Per-finding re-validation API (replaces the time sweep) ───────────────
-- Call when a specific finding's underlying evidence changes (true drift):
--   SELECT request_revalidation('F-0123');
-- This resets that ONE finding to 'pending', which fires the trigger above.
CREATE OR REPLACE FUNCTION request_revalidation(p_finding_id text) RETURNS boolean AS $fn$
DECLARE n int;
BEGIN
    UPDATE findings SET validation_status = 'pending'
     WHERE finding_id = p_finding_id AND validation_status <> 'pending';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 0 THEN
        -- already pending: signal anyway so the listener re-checks it
        PERFORM pg_notify('finding_validate', p_finding_id);
    END IF;
    RETURN n > 0;
END;
$fn$ LANGUAGE plpgsql;
