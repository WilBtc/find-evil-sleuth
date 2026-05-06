-- validator-query.sql
-- Returns all pending findings for a case with their original tool_call metadata.
-- Usage: psql $DSN -f scripts/validator-query.sql -v case_id='phase15-1778089502' -v specialist='disk'
--
-- If :specialist is not set, all specialists are included.
-- psql replaces :var with the supplied value; if undefined, the COALESCE returns the wildcard.

SELECT
    f.finding_id,
    f.case_id,
    f.specialist,
    f.claim,
    f.confidence,
    tc.tool_call_id::text  AS original_tc_id,
    tc.tool,
    tc.args::text          AS args_json,
    tc.exit_code           AS orig_exit_code
FROM findings f
JOIN tool_calls tc ON tc.tool_call_id = f.tool_call_id
WHERE f.validation_status = 'pending'
  AND f.case_id            = :'case_id'
  AND (:'specialist' = 'all' OR f.specialist = :'specialist')
ORDER BY f.finding_id;
