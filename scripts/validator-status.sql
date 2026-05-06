-- validator-status.sql
-- Check validation coverage for a case.
-- Usage: psql $DSN -f scripts/validator-status.sql -v case_id='phase15-1778089502'

SELECT
    validation_status,
    count(*) AS count
FROM findings
WHERE case_id = :'case_id'
GROUP BY validation_status
ORDER BY validation_status;
