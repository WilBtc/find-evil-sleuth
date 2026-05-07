-- find-evil-sleuth · migration 006 — output_* schema patterns → ^/scratch/
--
-- Tools that write output (tsk_recover, bulk_extractor, editcap, log2timeline,
-- psort, zeek, tshark, suricata) previously required output paths under /case/
-- (which is mounted read-only).  This migration updates args_schema JSON for
-- every tool that has an output_dir, output_file, or output property so those
-- fields now require ^/scratch/ instead, matching the new rw bind mount.
--
-- Input/image/pcap/rules/target properties that are read-only remain ^/case/.
-- Do NOT edit 002_tool_specs_seed.sql in place; this migration is the record.
--
-- NOTE: args_schema column is native jsonb; no cast needed.

UPDATE tool_specs
SET args_schema = jsonb_set(
    args_schema,
    '{properties,output_dir,pattern}',
    '"^/scratch/"'
)
WHERE tool IN ('tsk_recover', 'bulk_extractor', 'zeek', 'suricata')
  AND args_schema #>> '{properties,output_dir,pattern}' = '^/case/';

UPDATE tool_specs
SET args_schema = jsonb_set(
    args_schema,
    '{properties,output_file,pattern}',
    '"^/scratch/"'
)
WHERE tool IN ('log2timeline', 'psort', 'tshark')
  AND args_schema #>> '{properties,output_file,pattern}' = '^/case/';

UPDATE tool_specs
SET args_schema = jsonb_set(
    args_schema,
    '{properties,output,pattern}',
    '"^/scratch/"'
)
WHERE tool IN ('editcap')
  AND args_schema #>> '{properties,output,pattern}' = '^/case/';
