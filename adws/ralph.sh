#!/usr/bin/env bash
# ralph.sh — autonomous backlog driver for find-evil-sleuth.
#
# IndyDevDan-style outer loop: pick the first unchecked task in BACKLOG.md,
# hand it to `claude --print` with strict instructions, validate the result
# matches the task's "Done when" condition, tick the box, commit, repeat.
#
# Kill switches:
#   touch ~/.ralph-stop                  # graceful exit at next iteration boundary
#   pkill -f 'ralph.sh' / Ctrl-C         # immediate
#
# Caps:
#   RALPH_ITER_TIMEOUT_S=1800   per-iteration wall (claude + validation combined)
#   RALPH_MAX_ITERATIONS=20     hard ceiling per ralph run
#
# Logs every decision to obs (Sleuth.ralph.*) so cost guardian / kpi tracker
# can throttle.  No stdout secrets — model output goes to per-iter log files.

set -euo pipefail
cd "$(dirname "$0")/.."

ITER=0
MAX=${RALPH_MAX_ITERATIONS:-20}
ITER_TIMEOUT=${RALPH_ITER_TIMEOUT_S:-1800}
MODEL=${RALPH_MODEL:-claude-sonnet-4-6}
LOG_ROOT=${RALPH_LOG_ROOT:-./logs/ralph}
mkdir -p "$LOG_ROOT"

OBS_URL=${OBS_URL:-http://127.0.0.1:8910}

obs() {
    local type="$1"; shift
    local data="$*"
    curl -m 2 -s -o /dev/null -X POST -H 'content-type: application/json' \
        -d "$(jq -nc --arg t "$type" --argjson d "${data:-null}" '{type:$t,data:$d}')" \
        "$OBS_URL/event" 2>/dev/null || true
}

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
err()  { printf '\033[31m✗ %s\033[0m\n' "$*"; }

while [[ $ITER -lt $MAX ]]; do
    ITER=$((ITER+1))

    # Kill switch
    if [[ -f $HOME/.ralph-stop ]]; then
        bold "ralph: kill switch present (~/.ralph-stop) — exiting cleanly"
        obs "Sleuth.ralph.stop" '{"reason":"kill_switch"}'
        exit 0
    fi

    # Pick next unchecked task line from BACKLOG.md
    task_line=$(grep -nE '^\- \[ \] \*\*' BACKLOG.md | head -1 || true)
    if [[ -z $task_line ]]; then
        bold "ralph: no unchecked tasks left in BACKLOG.md — done"
        obs "Sleuth.ralph.complete" '{"iterations":'"$ITER"'}'
        exit 0
    fi

    line_no=${task_line%%:*}
    task_summary=$(printf '%s' "$task_line" | sed -E 's/^[0-9]+:- \[ \] \*\*([^*]+)\*\*.*/\1/')

    bold ""
    bold "═══ ralph iter $ITER/$MAX · task: $task_summary ═══"

    iter_log="$LOG_ROOT/iter-$(printf '%03d' $ITER)-$(date +%s).log"
    obs "Sleuth.ralph.iter.start" "$(jq -nc --arg t "$task_summary" --arg i "$ITER" \
        '{task:$t,iter:($i|tonumber),log:"'"$iter_log"'"}')"

    # Build the per-iteration prompt: full backlog context + identify the task
    prompt=$(cat <<EOF
You are a build agent for find-evil-sleuth, a SANS hackathon project.

Project root: $(pwd)
Plans: see plans/00-master-plan.md and plans/01..08
Phase 1 + 1.5 are DONE — substrate, broker, evidence-store, hooks, real podman exec.
Now executing Phase 2 from BACKLOG.md.

Your job for this iteration: complete EXACTLY this one task, then stop.

Task (from BACKLOG.md line $line_no):
    $task_summary

Read the full backlog entry for this task in BACKLOG.md to see the "Done when"
acceptance criterion and the files to touch. Implement the change, verify the
acceptance criterion locally, commit your work with a precise message, and push.

Hard rules:
  1. Do NOT mark tasks other than this one in BACKLOG.md.
  2. Use ./bin/sb and ./bin/es for any tool execution — never raw shell.
  3. Build with cargo on the dev server only (ssh wil@100.111.46.46) when needed;
     local edits + commit are fine from this machine.
  4. If you cannot complete the task in this single iteration, do not partially
     mark it complete — push WIP commits and exit, ralph will retry next iter.
  5. Acceptance proof goes in your final response: paste the command output that
     demonstrates "Done when" passed.

When the acceptance criterion is verified, change the line in BACKLOG.md from:
    - [ ] **$task_summary** ...
to:
    - [x] **$task_summary** ...
…and commit.
EOF
)

    # Run claude --print with the prompt, with timeout. Stream to log.
    info "Running claude (model=$MODEL, timeout=${ITER_TIMEOUT}s)…"
    set +e
    timeout "${ITER_TIMEOUT}s" claude --print --model "$MODEL" \
        --dangerously-skip-permissions \
        "$prompt" >"$iter_log" 2>&1
    ec=$?
    set -e

    if [[ $ec -ne 0 ]]; then
        err "claude exited $ec (timeout = 124). See $iter_log"
        obs "Sleuth.ralph.iter.failed" "$(jq -nc --arg ec "$ec" '{exit:($ec|tonumber)}')"
        # Don't tick the box; ralph retries next iteration.
        continue
    fi

    # Verify the box was ticked (claude's commit should have done it).
    if grep -qE "^\- \[x\] \*\*${task_summary}\*\*" BACKLOG.md 2>/dev/null; then
        ok "Box ticked: $task_summary"
        obs "Sleuth.ralph.iter.success" "$(jq -nc --arg t "$task_summary" '{task:$t}')"
    else
        err "Claude finished but BACKLOG.md still has [ ] for this task — retrying"
        obs "Sleuth.ralph.iter.unverified" "$(jq -nc --arg t "$task_summary" '{task:$t}')"
        continue
    fi

    # Push to gitea so dev-server can git pull
    git push gitea main 2>/dev/null || true
done

bold "ralph: hit MAX_ITERATIONS=$MAX — bailing"
obs "Sleuth.ralph.iter.cap" "$(jq -nc --arg m "$MAX" '{max:($m|tonumber)}')"
exit 0
