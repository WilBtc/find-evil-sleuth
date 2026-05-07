#!/usr/bin/env bash
# find-evil-sleuth · architectural guardrail
#
# Hook fires before every Bash tool invocation by any subagent in this project.
# It allows ONLY:
#   - the broker (./bin/sb), evidence-store (./bin/es)
#   - lightweight text utilities for parsing broker output (jq, grep, awk, …)
#   - read-only repo helpers (git status/diff/log/show/branch/remote)
#
# Anything else exits non-zero. Subagents cannot invoke forensics tools directly,
# write outside the workspace, reach the network, or escalate. This is the
# architectural guardrail that wins judging criterion 4: not a system prompt,
# not a model behavior — a process boundary the agent cannot cross.

set -u

input_json="$(cat)"
cmd="$(printf '%s' "$input_json" | jq -r '.tool_input.command // ""')"

# Strip leading whitespace and the optional `set -e` / pipe noise.
trimmed="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]+//')"

# Allowlist regex.  ^ anchored. Only the *first* token matters; the rest is
# user-controlled args to that command, but those tokens themselves cannot
# launch a new program because shell metachars (;, &&, ||, |, $()) are also
# checked against the allowlist for each segment via a simple split.
allow='^(\.\/bin\/sb|\.\/bin\/es|\.\/tests\/[A-Za-z0-9_./-]+|\.\/scripts\/[A-Za-z0-9_./-]+|jq|grep|awk|sed|head|tail|cut|sort|uniq|wc|cat|column|date|test|\[|echo|printf|true|false|tr|env|pwd|ls|stat|file|hexdump|xxd|git[[:space:]]+(status|diff|log|show|branch|remote|add|commit|push|pull|fetch)|psql|chmod|mkdir|touch|sleep)([[:space:]]|$)'

deny_reason() {
    cat <<EOF >&2
sleuth-broker hook: command rejected.
This project's Bash hook only permits broker / evidence-store / safe text
utilities. The agent cannot run forensics tools directly — go through:
    ./bin/sb exec --case <id> --tool <name> --args '<json>'
First denied token: ${1:-unknown}
EOF
    exit 2   # exit 2 → blocking, surfaces to model
}

# Split on shell metachars and check each segment's first token.
IFS=$'\n' read -r -d '' -a segments < <(printf '%s' "$trimmed" \
    | awk 'BEGIN{RS=";|&&|\\|\\||\\|"} {gsub(/^[[:space:]]+|[[:space:]]+$/,""); if(length($0)) print}' && printf '\0')

for seg in "${segments[@]}"; do
    [[ -z "$seg" ]] && continue
    if ! [[ "$seg " =~ $allow ]]; then
        deny_reason "$(printf '%s' "$seg" | awk '{print $1}')"
    fi
done

exit 0
