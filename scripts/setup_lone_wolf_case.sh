#!/usr/bin/env bash
set -e
EVIDENCE=/home/wil/projects/find-evil-sleuth/evidence-samples/lone-wolf
CASE_DIR=/home/wil/projects/find-evil-sleuth/cases/lone-wolf-disk

mkdir -p "$CASE_DIR"
for f in "$EVIDENCE"/LoneWolf.E0*; do
    base=$(basename "$f")
    if [ ! -e "$CASE_DIR/$base" ]; then
        ln -sf "$f" "$CASE_DIR/$base"
    fi
done
echo "Case directory setup complete:"
ls -la "$CASE_DIR/"
