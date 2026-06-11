INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'deep_carve', 'find-evil-sleuth/sift-full:latest',
  '{"type":"object","properties":{"image":{"type":"string","pattern":"^/case/"},"target":{"type":"string","pattern":"^/case/"}},"additionalProperties":false}',
  2400, 8192, 256, 'none', 'default'
) ON CONFLICT (tool) DO UPDATE SET image=EXCLUDED.image, timeout_s=EXCLUDED.timeout_s, memory_mb=EXCLUDED.memory_mb;
