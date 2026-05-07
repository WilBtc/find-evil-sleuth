-- find-evil-sleuth · SIFT integration (Phase 3.5.2)
-- Registers mmls-sift as a parallel tool routed through the SIFT image.
-- The existing mmls tool continues to use find-evil-sleuth/sleuthkit:latest.
-- mmls-sift uses find-evil-sleuth/sift:latest, proving SIFT routing works.
-- Idempotent: INSERT ... ON CONFLICT DO NOTHING.

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'mmls-sift',
  'find-evil-sleuth/sift:latest',
  '{
    "type": "object",
    "required": ["image"],
    "properties": {
      "image": {"type": "string", "pattern": "^/case/"},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  120, 1024, 128, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;
