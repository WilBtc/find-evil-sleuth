#!/usr/bin/env bash
# Cap parallel cargo rustc jobs in ~/.cargo/config.toml.
# Two parallel `cargo build` invocations on a 32-core box can each spawn
# 32 rustc processes — 64 concurrent rustc, each with multiple LLVM threads,
# easily pegs 32 cores at 200%+ each. Capping jobs to NCPU/2 prevents this.
set -euo pipefail

CONFIG="${CARGO_CONFIG:-$HOME/.cargo/config.toml}"
NCPU=$(nproc 2>/dev/null || echo 4)
JOBS=$(( NCPU / 2 ))
[[ $JOBS -lt 2 ]] && JOBS=2

mkdir -p "$(dirname "$CONFIG")"

if [[ -f "$CONFIG" ]] && grep -q '^\[build\]' "$CONFIG"; then
    if grep -q '^jobs *=' "$CONFIG"; then
        sed -i "s|^jobs *=.*|jobs = $JOBS|" "$CONFIG"
    else
        sed -i "/^\[build\]/a jobs = $JOBS" "$CONFIG"
    fi
else
    cat >> "$CONFIG" <<EOF

[build]
jobs = $JOBS
EOF
fi

echo "[cargo-jobs] $CONFIG: build.jobs = $JOBS  (ncpu=$NCPU)"
