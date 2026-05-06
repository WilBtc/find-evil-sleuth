# 04 · Subagents & Skills

> Six Claude Code subagents, each a thin loop over `./bin/sb` and `./bin/es`. Skills carry the playbooks. The model's only privileged action is reasoning — never direct shell.

## Tools allowed (PreToolUse hook)

```
^(./bin/sb|./bin/es|jq|grep|awk|sed|head|tail|cut|sort|uniq|wc|cat|column|date|test|\\[) 
```

Anything else exits 1. This is enforced regardless of which subagent is running.

## Agents

### `triage` (`.claude/agents/find-evil/triage.md`)
- **Tools:** `Bash` (broker subset), `Read` (case dir manifest only)
- **Model:** Sonnet 4.6
- **Loop:** `file /case/**/*` via broker `file` tool → classify → `INSERT INTO case_plan` → emit dispatch JSON to ADW driver
- **Never** runs analysis itself

### `disk-specialist`
- **Tools allowed via broker:** `mmls fls icat tsk_recover tsk_loaddb log2timeline.py psort.py yara bulk_extractor strings file xxd`
- **Skill body:** `disk-forensics/SKILL.md` (playbook below)
- **Stop condition:** validator queue for this specialist drains OR self_corrections >= 3

### `memory-specialist`
- **Tools:** `vol3` only (one binary, many plugins via args)
- **Skill body:** `memory-forensics/SKILL.md`
- **Self-correction hot path:** profile-mismatch → re-run `windows.info` → derive → patch case_plan → retry

### `network-specialist`
- **Tools:** `tshark editcap mergecap capinfos zeek suricata ngrep`
- **Skill body:** `network-forensics/SKILL.md`
- **Self-correction hot path:** truncated/corrupt pcap → `editcap -E 0` recover → re-tshark with `confidence=partial`

### `validator`
- **Tools:** `./bin/sb exec --validation`, `./bin/es validate`
- **Model:** Opus 4.7 (accuracy is the criterion this agent owns)
- **Loop:** dequeue finding → re-execute its tool_call (validation flag) → diff hashes → set status

### `narrator`
- **Tools:** `./bin/es search`, `./bin/es graph cypher`, write to `report.md` only
- **Model:** Opus 4.7 (best-of-N=3, judged by Opus too)
- **Constraint:** every paragraph must contain at least one `[F-NNN]`. Validated by post-Stop hook.

## Skill bodies (compressed)

### `dfir-triage/SKILL.md`
1. Walk `/case/`. For each file:
   - Run `./bin/sb exec --tool file --args '{"path":"…"}'`
   - Run `./bin/sb exec --tool blake3 --args '{"path":"…"}'`
2. Bucket: `*.E01|*.dd|*.raw + 'partition table'` → disk; `*.raw|*.mem|*.vmem + 'data'` → memory; `*.pcap|*.pcapng` → network; `evtx|.log` → log (folded into disk).
3. Write `case_plan` rows; emit JSON dispatch.

### `disk-forensics/SKILL.md`
Playbook for each disk image:
1. `mmls` → partition map → for each NTFS partition:
2. `fls -r -m / -o <offset>` → mactime body → `log2timeline.py`/`psort.py` → save artifact, record finding for any anomaly window.
3. `tsk_recover -e` → recover deleted; yara-scan recovered tree.
4. `bulk_extractor -E all` → carved IOCs → record findings (+ pgvector dedup).
5. Emit AGE: `(File {path,sha,partition})` and `(File)-[:WAS_DELETED_AT]->(File {…})`.

### `memory-forensics/SKILL.md`
Playbook (Windows; Linux profile branch is stretch):
1. `windows.info` → store profile in `case_plan.config.os_profile`
2. `windows.pslist`, `windows.pstree` → AGE process tree
3. `windows.cmdline` → record any base64/encoded commands (heuristic + yara)
4. `windows.malfind` → record each PID flagged with offset+permissions
5. `windows.netscan` → AGE `(Process)-[:CONNECTED_TO]->(NetworkEndpoint)`
6. `windows.svcscan` → persistence findings
7. `windows.registry.printkey` on `Run`, `RunOnce`, `Image File Execution Options` → persistence findings

### `network-forensics/SKILL.md`
1. `capinfos` → integrity, range
2. `tshark -r … -T fields -e ip.src -e ip.dst -e tcp.port -e dns.qry.name` → record top talkers / DNS oddities
3. `zeek -r …` → conn.log + http.log + ssl.log + dns.log → record alerts
4. `suricata -r … -l /scratch/suri/` (with ET-Open in image) → eve.json → record alerts (mitre_technique from rule meta)
5. AGE: `(Process)-[:CONNECTED_TO]->(NetworkEndpoint)` joined later via memory specialist's pid→port map

### `findings-validator/SKILL.md`
For each pending finding:
1. Look up `tool_calls.args` from `tool_call_id`
2. `./bin/sb exec --validation --tool <t> --args <a>` → new tool_call_id
3. If `stdout_hash` matches AND `exit_code == 0` → `confirmed`
4. If hashes differ but new exit==0 → `inconclusive` (output drift; investigate)
5. If new exit != 0 → `refuted` (original may have been a one-time fluke)
6. `./bin/es validate --finding <id> --result <r> --diff '<json>'`
7. If three findings in a row come back `inconclusive`, escalate to ADW driver to halt narrator.

### `ir-narrator/SKILL.md`
Read-only. Queries:
```sql
SELECT * FROM findings WHERE case_id=$1 AND validation_status='confirmed'
  AND superseded_by IS NULL ORDER BY mitre_technique;
```
Plus AGE attack-graph queries to assemble a timeline. Section template:
```
## Executive Summary
…[F-001][F-014]…

## Initial Access (T1566.x)
…

## Execution (T1059.x)
…

## Persistence
…

## Lateral Movement
…

## Exfiltration
…

## Self-Corrections During Investigation
| Attempt | Failed tool | Reason | Recovery | Outcome |
|--|--|--|--|--|
| 1 | vol3 windows.malfind | profile mismatch | windows.info → derive | confirmed |
| 2 | tshark -r evil.pcap | truncated EOF | editcap -E 0 → recover | partial |

## Indicators of Compromise
…
```

Stop hook validates every paragraph has `[F-NNN]` cites; if not, the report is rejected and narrator re-runs (best-of-N).
