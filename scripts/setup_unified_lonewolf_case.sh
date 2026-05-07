#!/usr/bin/env bash
# setup_unified_lonewolf_case.sh
# Creates a unified LoneWolf case by:
#  1. Creating the case directory with evidence symlinks
#  2. Inserting case, case_plan, and findings into Postgres
#     (copied from the 3 specialist cases: lone-wolf-disk/memory/network)
#
# The case is initialized at status='narrating' so that investigate.sh
# picks up directly at the NARRATING state (all findings already confirmed).
set -e

CASE_ID="${1:-lone-wolf-1778168581}"
CASE_DIR="/home/wil/projects/find-evil-sleuth/cases/${CASE_ID}"
EVIDENCE="/home/wil/projects/find-evil-sleuth/evidence-samples/lone-wolf"
DB="postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"

echo "=== Setting up unified LoneWolf case: ${CASE_ID} ==="

mkdir -p "${CASE_DIR}"

for f in "${EVIDENCE}"/LoneWolf.E0* "${EVIDENCE}"/memdump.mem "${EVIDENCE}"/m57-net-2009-12-06.pcap.gz; do
    base=$(basename "$f")
    if [ ! -e "${CASE_DIR}/${base}" ]; then
        ln -sf "$f" "${CASE_DIR}/${base}"
    fi
done

echo "Evidence symlinks:"
ls -la "${CASE_DIR}/"

echo "=== Inserting case into Postgres ==="
psql "$DB" << SQL
INSERT INTO cases (case_id, name, status)
VALUES ('${CASE_ID}', 'LoneWolf 2018 - Full Investigation', 'narrating')
ON CONFLICT (case_id) DO UPDATE SET status = 'narrating';

INSERT INTO case_plan (case_id, specialist, config)
VALUES
  ('${CASE_ID}', 'disk',    '{"images":["LoneWolf.E01"],"tool_budget":20,"classified_by":"manual","classified_at":"2026-05-07T00:00:00Z"}'::jsonb),
  ('${CASE_ID}', 'memory',  '{"images":["memdump.mem"],"tool_budget":20,"classified_by":"manual","classified_at":"2026-05-07T00:00:00Z"}'::jsonb),
  ('${CASE_ID}', 'network', '{"images":["m57-net-2009-12-06.pcap.gz"],"tool_budget":20,"classified_by":"manual","classified_at":"2026-05-07T00:00:00Z"}'::jsonb)
ON CONFLICT (case_id, specialist) DO NOTHING;
SQL

echo "=== Copying confirmed findings from specialist cases ==="
psql "$DB" << 'SQL'
INSERT INTO findings (case_id, specialist, claim, tool_call_id, mitre_technique, confidence, validation_status)
SELECT 'lone-wolf-1778168581', specialist, claim, tool_call_id, mitre_technique, confidence, 'confirmed'
FROM findings
WHERE case_id IN ('lone-wolf-disk', 'lone-wolf-memory', 'lone-wolf-network')
  AND validation_status = 'confirmed'
ON CONFLICT DO NOTHING;
SQL

echo "=== Verifying findings count ==="
psql "$DB" << 'SQL'
SELECT specialist, validation_status, count(*)
FROM findings
WHERE case_id = 'lone-wolf-1778168581'
GROUP BY specialist, validation_status
ORDER BY specialist;
SQL

echo "=== Done. Case ${CASE_ID} ready for narration. ==="
echo "Run: ./scripts/investigate.sh cases/${CASE_ID}/"
