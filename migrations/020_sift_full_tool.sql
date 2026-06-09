-- find-evil-sleuth · Full SIFT integration (Backlog 5.4.1)
-- Registers mmls-sift-full, routed through the FULL SANS SIFT distribution
-- image find-evil-sleuth/sift-full:latest (digitalsleuth/sift-remnux base, ~15 GB,
-- complete Sleuth Kit + Volatility 2/3 + Plaso + Zeek + YARA toolchain).
--
-- This is the heavyweight counterpart to mmls-sift (013), which routes through
-- the lightweight per-tool sleuthkit image for live-demo speed. mmls-sift-full
-- proves integration with the real, unabridged SIFT distribution.
-- Idempotent: INSERT ... ON CONFLICT DO NOTHING.

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'mmls-sift-full',
  'find-evil-sleuth/sift-full:latest',
  '{
    "type": "object",
    "required": ["image"],
    "properties": {
      "image": {"type": "string", "pattern": "^/case/"},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  300, 2048, 256, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;
