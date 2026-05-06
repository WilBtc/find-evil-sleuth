#!/usr/bin/env bash
# Post-tool obs emitter. If the just-executed Bash invoked the broker, parse
# the JSON receipt from its stdout and forward to agent-obs:8910 as an event.
# Soft-fails: never block tool flow even if obs is down.

set -u

input_json="$(cat || true)"

# Only react to broker invocations
cmd="$(printf '%s' "$input_json" | jq -r '.tool_input.command // ""' 2>/dev/null)"
[[ "$cmd" =~ \./bin/sb[[:space:]]+exec ]] || exit 0

obs_url="${OBS_URL:-http://100.119.146.74:8910}"
output="$(printf '%s' "$input_json" | jq -r '.tool_response.output // ""' 2>/dev/null)"
receipt="$(printf '%s' "$output" | jq -c '.' 2>/dev/null)"
[[ -z "$receipt" || "$receipt" == "null" ]] && exit 0

curl -m 2 -s -o /dev/null -X POST -H 'content-type: application/json' \
    -d "$(jq -nc --argjson r "$receipt" '{type:"Sleuth.tool.executed", data:$r}')" \
    "$obs_url/event" || true

exit 0
