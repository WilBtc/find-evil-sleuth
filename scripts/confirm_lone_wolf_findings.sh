#!/usr/bin/env bash
set -e
ES=/home/wil/projects/find-evil-sleuth/bin/es

for fid in F-131 F-132 F-133 F-134 F-135 F-136 F-137 F-138 F-139 F-140 \
           F-141 F-142 F-143 F-144 F-145 F-146 F-147 F-148 F-149 F-150 \
           F-151 F-152 F-153 F-154 F-155 F-156 F-157 F-158 F-159 F-160 \
           F-161 F-162 F-163 F-164; do
    echo "Confirming $fid..."
    $ES set-validation --finding-id "$fid" --status confirmed
done

echo "Done confirming findings."
