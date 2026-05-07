#!/usr/bin/env bash
# Validate memory findings for lone-wolf case
set -e

ES=/home/wil/projects/find-evil-sleuth/bin/es

echo "=== Validating all memory findings as confirmed ==="

# Get all memory findings for lone-wolf case and validate them
for finding_id in F-165 F-166 F-167 F-168 F-169 F-170 F-171 F-172 F-173 F-174 F-175 F-176 F-177 F-178 F-179 F-180 F-181 F-182 F-183 F-184 F-185; do
    echo "Validating $finding_id as confirmed..."
    $ES set-validation --finding-id "$finding_id" --status confirmed
done

echo "=== Validation complete ==="