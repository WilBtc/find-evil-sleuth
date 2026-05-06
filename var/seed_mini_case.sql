-- Seed mini case with data from phase15-1778089502 for acceptance testing
BEGIN;

INSERT INTO cases (case_id, name, status)
VALUES ('mini', 'mini', 'narrating')
ON CONFLICT (case_id) DO UPDATE SET status = 'narrating', finished_at = NULL;

INSERT INTO case_plan (case_id, specialist, config)
SELECT 'mini', specialist, config
FROM case_plan
WHERE case_id = 'phase15-1778089502'
ON CONFLICT DO NOTHING;

INSERT INTO findings (
    finding_id, case_id, specialist, claim, tool_call_id,
    artifact_hash, byte_offset, confidence, validation_status,
    last_validated_at, mitre_technique
)
SELECT
    'M-' || substring(finding_id FROM 3),
    'mini',
    specialist,
    claim,
    tool_call_id,
    artifact_hash,
    byte_offset,
    confidence,
    'confirmed',
    now(),
    mitre_technique
FROM findings
WHERE case_id = 'phase15-1778089502'
AND validation_status = 'confirmed'
ON CONFLICT (finding_id) DO NOTHING;

COMMIT;
