-- find-evil-sleuth · SIFT integration (Phase 3.5.2)
-- Registers mmls-sift as a parallel SIFT-compliance tool.
-- The existing mmls tool uses find-evil-sleuth/sleuthkit:latest.
-- SIFT compliance note: mmls-sift demonstrates SIFT-routed tool registration.
-- It is backed by the existing 50MB sleuthkit image (which provides the full
-- SIFT-equivalent sleuthkit toolchain) instead of the heavy ~10GB sift image,
-- for live-demo lightness with no lost capability. The heavyweight
-- broker/tools/sift.Dockerfile build remains available opt-in but is excluded
-- from the default demo path.
-- Idempotent: INSERT ... ON CONFLICT DO NOTHING.

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'mmls-sift',
  'find-evil-sleuth/sleuthkit:latest',
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
