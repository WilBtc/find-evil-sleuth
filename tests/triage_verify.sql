SELECT
  case_id,
  specialist,
  config->>'classified_by' AS classified_by,
  jsonb_array_length(config->'images') AS image_count
FROM case_plan
WHERE case_id = 'synthetic-triage-001'
ORDER BY specialist;
