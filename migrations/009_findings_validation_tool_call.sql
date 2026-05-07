-- find-evil-sleuth · add validation_tool_call_id to findings (Phase 3.2.2)
-- Stores the UUID of the tool_call that was used to re-run the original
-- tool during validation, making the audit trail fully navigable from a
-- finding to both its original tool_call and its validating tool_call.
--
-- Note: tool_calls uses a composite PK (started_at, tool_call_id), so a
-- referential FK from findings is not straightforward.  We store the UUID
-- as a plain column (no FK) and join on tool_call_id in queries; this is
-- safe because tool_call_id has a gen_random_uuid() default and is part of
-- the PK, so it is effectively unique.

ALTER TABLE findings
    ADD COLUMN IF NOT EXISTS validation_tool_call_id uuid;

CREATE INDEX IF NOT EXISTS ix_findings_validation_tc
    ON findings (validation_tool_call_id)
    WHERE validation_tool_call_id IS NOT NULL;
