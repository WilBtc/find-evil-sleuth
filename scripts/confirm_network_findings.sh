#!/usr/bin/env bash
# Set all lone-wolf-network network findings to confirmed
set -e

ES=/home/wil/projects/find-evil-sleuth/bin/es
DB=postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth

for fid in F-191 F-192 F-193 F-194 F-195 F-196 F-197 F-198 F-199 F-200 \
           F-201 F-202 F-203 F-204 F-205 F-206 F-207 F-208 F-209 F-210 \
           F-211 F-212 F-213 F-214; do
    echo "Setting $fid to confirmed..."
    $ES set-validation --finding-id "$fid" --status confirmed
done

echo ""
echo "=== Final acceptance criterion check ==="
psql "$DB" -c "SELECT count(*) FROM findings WHERE case_id LIKE 'lone-wolf-%' AND specialist='network' AND validation_status='confirmed';"
