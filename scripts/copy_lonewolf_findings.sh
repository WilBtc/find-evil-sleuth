#!/usr/bin/env bash
# Copy confirmed LoneWolf findings from specialist cases into unified case
# Generates new F-NNN IDs starting from F-215
set -e
DB="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"
CASE_ID="lone-wolf-1778168581"

psql "$DB" << 'SQL'
DO $$
DECLARE
    next_num INTEGER;
    r RECORD;
    new_id TEXT;
BEGIN
    SELECT COALESCE(
        MAX(CAST(SUBSTRING(finding_id FROM 3) AS INTEGER)), 214
    ) + 1
    INTO next_num
    FROM findings
    WHERE finding_id ~ '^F-[0-9]+$';

    FOR r IN
        SELECT specialist, claim, tool_call_id, mitre_technique, confidence
        FROM findings
        WHERE case_id IN ('lone-wolf-disk', 'lone-wolf-memory', 'lone-wolf-network')
          AND validation_status = 'confirmed'
        ORDER BY case_id, finding_id
    LOOP
        new_id := 'F-' || LPAD(next_num::TEXT, 3, '0');
        INSERT INTO findings (finding_id, case_id, specialist, claim, tool_call_id, mitre_technique, confidence, validation_status)
        VALUES (new_id, 'lone-wolf-1778168581', r.specialist, r.claim, r.tool_call_id, r.mitre_technique, r.confidence, 'confirmed');
        next_num := next_num + 1;
    END LOOP;

    RAISE NOTICE 'Inserted findings up to F-%', LPAD((next_num - 1)::TEXT, 3, '0');
END $$;
SQL
