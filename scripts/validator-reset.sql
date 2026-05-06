-- validator-reset.sql
-- Reset validation_status back to 'pending' for a case+specialist.
-- Used to re-run the validator after fixing bugs.
-- Usage: psql $DSN -f scripts/validator-reset.sql -v case_id='phase15-1778089502' -v specialist='disk'

UPDATE findings
   SET validation_status  = 'pending',
       last_validated_at  = NULL
 WHERE case_id            = :'case_id'
   AND (:'specialist' = 'all' OR specialist = :'specialist');

SELECT count(*) AS reset_count FROM findings
 WHERE case_id = :'case_id'
   AND validation_status = 'pending';
