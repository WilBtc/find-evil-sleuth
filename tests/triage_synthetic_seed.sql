-- Synthetic 3-evidence case seed for triage acceptance test
-- Run: psql $DATABASE_URL -f tests/triage_synthetic_seed.sql

INSERT INTO cases (case_id, name)
VALUES ('synthetic-triage-001', 'synthetic-triage-001')
ON CONFLICT DO NOTHING;

INSERT INTO case_plan (case_id, specialist, config)
VALUES
  ('synthetic-triage-001', 'disk', '{
    "images": ["disk.img"],
    "tool_budget": 20,
    "evidence_hashes": {},
    "classified_by": "dfir-triage",
    "classified_at": "2026-05-06T00:00:00Z"
  }'::jsonb),
  ('synthetic-triage-001', 'memory', '{
    "images": ["memory.mem"],
    "tool_budget": 15,
    "evidence_hashes": {},
    "classified_by": "dfir-triage",
    "classified_at": "2026-05-06T00:00:00Z"
  }'::jsonb),
  ('synthetic-triage-001', 'network', '{
    "images": ["traffic.pcap"],
    "tool_budget": 15,
    "evidence_hashes": {},
    "classified_by": "dfir-triage",
    "classified_at": "2026-05-06T00:00:00Z"
  }'::jsonb)
ON CONFLICT (case_id, specialist) DO UPDATE SET config = EXCLUDED.config;
