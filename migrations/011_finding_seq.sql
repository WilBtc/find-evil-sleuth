-- Migration 011: Replace MAX(...)+1 F-NNN allocation with a SEQUENCE
-- Concurrent specialists race on MAX+1 and collide on PK insert. A SEQUENCE
-- is atomic and collision-free under any concurrency level.

CREATE SEQUENCE IF NOT EXISTS finding_seq;

-- Seed the sequence to the current maximum so existing findings are not
-- re-used. If the table is empty, start at 1.
SELECT setval(
    'finding_seq',
    COALESCE(
        MAX(NULLIF(regexp_replace(finding_id, '\D', '', 'g'), '')::bigint),
        0
    )
)
FROM findings;
