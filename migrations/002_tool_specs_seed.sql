-- find-evil-sleuth · tool_specs seed (Phase 2.1.1)
-- Registers all 9+ forensics tools used by the specialist subagents.
-- Idempotent: INSERT ... ON CONFLICT DO NOTHING.

-- ─────────────────────────────────────────────────────────────────────────────
-- SleuthKit tools (image: find-evil-sleuth/sleuthkit:latest)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'mmls',
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

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'fls',
  'find-evil-sleuth/sleuthkit:latest',
  '{
    "type": "object",
    "required": ["image"],
    "properties": {
      "image":      {"type": "string", "pattern": "^/case/"},
      "offset":     {"type": "integer", "minimum": 0},
      "inode":      {"type": "integer", "minimum": 0},
      "recursive":  {"type": "boolean"},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  300, 2048, 128, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'icat',
  'find-evil-sleuth/sleuthkit:latest',
  '{
    "type": "object",
    "required": ["image", "inode"],
    "properties": {
      "image":      {"type": "string", "pattern": "^/case/"},
      "inode":      {"type": "integer", "minimum": 0},
      "offset":     {"type": "integer", "minimum": 0},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  300, 2048, 128, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'tsk_recover',
  'find-evil-sleuth/sleuthkit:latest',
  '{
    "type": "object",
    "required": ["image", "output_dir"],
    "properties": {
      "image":      {"type": "string", "pattern": "^/case/"},
      "output_dir": {"type": "string", "pattern": "^/case/"},
      "offset":     {"type": "integer", "minimum": 0},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  600, 4096, 256, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Plaso / log2timeline (image: find-evil-sleuth/plaso:latest)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'log2timeline',
  'find-evil-sleuth/plaso:latest',
  '{
    "type": "object",
    "required": ["image", "output_file"],
    "properties": {
      "image":       {"type": "string", "pattern": "^/case/"},
      "output_file": {"type": "string", "pattern": "^/case/"},
      "parsers":     {"type": "string"},
      "extra_args":  {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  1800, 8192, 256, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'psort',
  'find-evil-sleuth/plaso:latest',
  '{
    "type": "object",
    "required": ["storage_file"],
    "properties": {
      "storage_file": {"type": "string", "pattern": "^/case/"},
      "output_file":  {"type": "string", "pattern": "^/case/"},
      "filter":       {"type": "string"},
      "output_format":{"type": "string"},
      "extra_args":   {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  600, 4096, 128, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Volatility 3 (image: find-evil-sleuth/volatility3:latest)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'vol3',
  'find-evil-sleuth/volatility3:latest',
  '{
    "type": "object",
    "required": ["image", "plugin"],
    "properties": {
      "image":      {"type": "string", "pattern": "^/case/"},
      "plugin":     {"type": "string"},
      "os_profile": {"type": "string"},
      "pid":        {"type": "integer", "minimum": 0},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  600, 8192, 256, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- tshark / editcap (image: find-evil-sleuth/tshark:latest)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'tshark',
  'find-evil-sleuth/tshark:latest',
  '{
    "type": "object",
    "required": ["pcap"],
    "properties": {
      "pcap":       {"type": "string", "pattern": "^/case/"},
      "display_filter": {"type": "string"},
      "fields":     {"type": "array", "items": {"type": "string"}},
      "output_file":{"type": "string", "pattern": "^/case/"},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  300, 2048, 128, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'editcap',
  'find-evil-sleuth/tshark:latest',
  '{
    "type": "object",
    "required": ["input", "output"],
    "properties": {
      "input":      {"type": "string", "pattern": "^/case/"},
      "output":     {"type": "string", "pattern": "^/case/"},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  120, 1024, 64, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Zeek (image: find-evil-sleuth/zeek:latest)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'zeek',
  'find-evil-sleuth/zeek:latest',
  '{
    "type": "object",
    "required": ["pcap"],
    "properties": {
      "pcap":        {"type": "string", "pattern": "^/case/"},
      "output_dir":  {"type": "string", "pattern": "^/case/"},
      "scripts":     {"type": "array", "items": {"type": "string"}},
      "extra_args":  {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  600, 4096, 256, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Suricata (image: find-evil-sleuth/suricata:latest)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'suricata',
  'find-evil-sleuth/suricata:latest',
  '{
    "type": "object",
    "required": ["pcap"],
    "properties": {
      "pcap":       {"type": "string", "pattern": "^/case/"},
      "output_dir": {"type": "string", "pattern": "^/case/"},
      "rules_dir":  {"type": "string"},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  600, 4096, 256, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- YARA (image: find-evil-sleuth/yara:latest)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'yara',
  'find-evil-sleuth/yara:latest',
  '{
    "type": "object",
    "required": ["rules", "target"],
    "properties": {
      "rules":      {"type": "string", "pattern": "^/case/"},
      "target":     {"type": "string", "pattern": "^/case/"},
      "recursive":  {"type": "boolean"},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  300, 2048, 128, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- bulk_extractor (image: find-evil-sleuth/sleuthkit:latest — ships it)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO tool_specs (tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile)
VALUES (
  'bulk_extractor',
  'find-evil-sleuth/sleuthkit:latest',
  '{
    "type": "object",
    "required": ["image", "output_dir"],
    "properties": {
      "image":      {"type": "string", "pattern": "^/case/"},
      "output_dir": {"type": "string", "pattern": "^/case/"},
      "extra_args": {"type": "array", "items": {"type": "string"}}
    },
    "additionalProperties": false
  }',
  900, 8192, 256, 'none', 'default'
) ON CONFLICT (tool) DO NOTHING;
