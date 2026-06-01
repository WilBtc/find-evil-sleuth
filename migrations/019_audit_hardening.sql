-- find-evil-sleuth · audit hardening (efficiency + safety, from the 2026-06-01 audit)
-- Two low-risk, win-relevant fixes:
--   #10 add the secondary index that the "<100 ms cite" SLA needs (tool_calls is a
--       Timescale hypertable PK'd on started_at — case-scoped lookups full-scan today).
--   #8  cap extra_args length so a caller/LLM cannot splat arbitrary argv into a
--       sandboxed tool (defence-in-depth on the validated-argv guardrail).

-- ── #10 cite-path index ──────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS ix_tool_calls_case_started
    ON tool_calls (case_id, started_at, tool_call_id);

-- ── #8 bound extra_args (and zeek.scripts) in every tool's arg schema ─────────
UPDATE tool_specs
   SET args_schema = jsonb_set(args_schema::jsonb,
                               '{properties,extra_args,maxItems}', '8'::jsonb)
 WHERE (args_schema::jsonb -> 'properties') ? 'extra_args';

UPDATE tool_specs
   SET args_schema = jsonb_set(args_schema::jsonb,
                               '{properties,scripts,maxItems}', '8'::jsonb)
 WHERE (args_schema::jsonb -> 'properties') ? 'scripts';
