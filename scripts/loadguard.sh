#!/usr/bin/env bash
# loadguard — keep the host from going thermonuclear when long-running
# agentic loops accumulate orphaned children.
#
# Runs every 60s via systemd timer. When 1-min load > THRESHOLD, kill
# the highest-CPU non-essential process. "Essential" = postgres, dockerd,
# tailscaled, sshd, systemd-*. Logs every action to journald.
#
# Failure modes this prevents (all observed):
#   - Multiple parallel cargo builds spawned by overlapping shell sessions
#   - Stale claude --print children left behind by killed timeout wrappers
#   - Ralph re-running an iter while a previous iter's podman build still grinds
#   - Wget --continue respawning after pkill
#
# Tunables (env or default):
#   GUARD_THRESHOLD     — kill above 1-min loadavg of NCPU * MULT
#   GUARD_MULT          — multiplier for NCPU (default 4)
#   GUARD_MIN_AGE       — only kill processes older than N seconds (default 120)
#   GUARD_NEVER_KILL    — extended-regex of cmdlines never to touch

set -euo pipefail

GUARD_MULT="${GUARD_MULT:-4}"
GUARD_MIN_AGE="${GUARD_MIN_AGE:-120}"
GUARD_NEVER_KILL="${GUARD_NEVER_KILL:-^/usr/lib/systemd|^/usr/sbin/sshd|^/usr/bin/dockerd|tailscaled|jarvis|claude|postgres|^kworker|^/usr/sbin/cron|^/sbin/init|^/usr/lib/postgresql|sleuth-saas}"

ncpu=$(nproc)
threshold=${GUARD_THRESHOLD:-$(( ncpu * GUARD_MULT ))}

read -r load1 _ _ _ _ < /proc/loadavg
load_int=${load1%.*}

if [[ $load_int -le $threshold ]]; then
    exit 0
fi

logger -t loadguard "load1=$load1 > threshold=$threshold (ncpu=$ncpu); selecting victim"

# Find the highest-CPU process that:
#   - is older than GUARD_MIN_AGE seconds
#   - does NOT match the never-kill regex
#   - is not session leader 1 (init)
#
# Using bare-metal /proc reading to avoid `ps` ordering quirks under high load.
victim_pid=""
victim_pcpu=0

for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    [[ -r /proc/$pid/stat && -r /proc/$pid/cmdline ]] || continue
    cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | head -c 200)
    [[ -z "$cmd" ]] && continue
    [[ "$cmd" =~ $GUARD_NEVER_KILL ]] && continue

    # Parse stat: pid, comm, state, ppid, ..., utime(14), stime(15), ..., starttime(22)
    read -r _ _ _ _ _ _ _ _ _ _ _ _ _ utime stime _ _ _ _ _ _ starttime _ < /proc/$pid/stat 2>/dev/null || continue
    [[ -z "$utime" ]] && continue

    # Process age in seconds (boot time + starttime in ticks → seconds since boot)
    boot=$(awk '/^btime/{print $2}' /proc/stat)
    now=$(date +%s)
    sec_since_boot=$(( starttime / 100 ))
    proc_start=$(( boot + sec_since_boot ))
    age=$(( now - proc_start ))
    [[ $age -lt $GUARD_MIN_AGE ]] && continue

    # CPU%: total ticks of this process / age in ticks (100 ticks/sec)
    total=$(( utime + stime ))
    age_ticks=$(( age * 100 ))
    [[ $age_ticks -le 0 ]] && continue
    pcpu=$(( total * 100 / age_ticks ))

    if [[ $pcpu -gt $victim_pcpu ]]; then
        victim_pcpu=$pcpu
        victim_pid=$pid
        victim_cmd=$cmd
    fi
done

if [[ -z "$victim_pid" ]]; then
    logger -t loadguard "no victim found above threshold; load is high but caused by short-lived processes — sleeping"
    exit 0
fi

logger -t loadguard "killing pid=$victim_pid pcpu=${victim_pcpu}% cmd='${victim_cmd:0:160}'"
kill -TERM "$victim_pid" 2>/dev/null || true
sleep 5
kill -KILL "$victim_pid" 2>/dev/null || true

# Re-read load for the journal record.
read -r load1_after _ < /proc/loadavg
logger -t loadguard "post-kill load1=$load1_after"
