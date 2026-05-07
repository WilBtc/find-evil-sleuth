-- find-evil-sleuth · Demo theatre seed (Phase 5.3.1)
-- Ensures the lone-wolf case row exists and inserts an initial tool_call
-- so the case detail page shows activity immediately on demo day.
-- The sleuth-saas theatre cron will add fresh rows every 60 s when
-- ~/.sleuth-saas-theatre exists.
-- Idempotent: INSERT ... ON CONFLICT DO NOTHING.

INSERT INTO cases (case_id, name, status)
VALUES (
    'lone-wolf-1778168581',
    'LoneWolf — SANS Hackathon Demo',
    'complete'
) ON CONFLICT (case_id) DO NOTHING;

INSERT INTO tool_calls
    (case_id, tool, args, exit_code, duration_ms, is_validation)
VALUES (
    'lone-wolf-1778168581',
    'fls',
    '{"image":"/case/LoneWolf.E01","extra_args":["-r","-l"]}',
    0,
    420,
    true
);
