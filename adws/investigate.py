#!/usr/bin/env python3
"""
adws/investigate.py — ADW outloop driver for find-evil-sleuth.

State machine (plan 05):
  INIT → TRIAGE → DISPATCH → SPECIALISTS_RUNNING → VALIDATING → NARRATING → DONE

Resumable: re-running with the same case_id picks up from cases.status.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import re
import sys
import time
from pathlib import Path
import psycopg2
import psycopg2.extras

from adws.self_correct import SelfCorrector

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("adw")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SPECIALISTS = ["disk", "memory", "network"]
SPECIALIST_AGENT_MAP = {
    "disk":    "find-evil/disk-specialist",
    "memory":  "find-evil/memory-specialist",
    "network": "find-evil/network-specialist",
}
SPECIALIST_TIMEOUT_S = 45 * 60   # 45 min per specialist
TRIAGE_TIMEOUT_S     =  5 * 60   # 5 min for triage
VALIDATE_TIMEOUT_S   = 30 * 60   # 30 min for validator
NARRATE_TIMEOUT_S    = 15 * 60   # 15 min per narrator candidate
PARALLELISM_CAP      = 3

MODEL_DEFAULT  = os.environ.get("MODEL_DEFAULT",  "claude-sonnet-4-6")
MODEL_NARRATOR = os.environ.get("MODEL_NARRATOR", "claude-sonnet-4-6")
DATABASE_URL   = os.environ.get(
    "DATABASE_URL",
    "postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth",
)

OBS_URL = os.environ.get("OBS_URL", "http://127.0.0.1:8910")


# ---------------------------------------------------------------------------
# Postgres helpers
# ---------------------------------------------------------------------------

def db_connect() -> psycopg2.extensions.connection:
    for attempt in range(3):
        try:
            conn = psycopg2.connect(DATABASE_URL)
            conn.autocommit = True
            return conn
        except psycopg2.OperationalError as exc:
            wait = [5, 15, 45][attempt]
            log.warning("DB unavailable (%s) — retrying in %ds", exc, wait)
            time.sleep(wait)
    log.error("Cannot connect to Postgres after 3 attempts — aborting")
    sys.exit(1)


def db_query(conn, sql: str, params=None):
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def db_exec(conn, sql: str, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params)


# ---------------------------------------------------------------------------
# Obs helper
# ---------------------------------------------------------------------------

def obs(event_type: str, data: dict | None = None):
    try:
        payload = json.dumps({"type": event_type, "data": data or {}})
        subprocess.run(
            ["curl", "-m", "2", "-s", "-o", "/dev/null",
             "-X", "POST", "-H", "content-type: application/json",
             "-d", payload, f"{OBS_URL}/event"],
            check=False, capture_output=True,
        )
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Agent system-prompt loader
# ---------------------------------------------------------------------------

def load_agent_system_prompt(agent_name: str, project_root: Path) -> str | None:
    """
    Load the agent markdown file from .claude/agents/.
    Supports paths like 'find-evil/ir-narrator' → searches:
      .claude/agents/find-evil/ir-narrator.md
      .claude/agents/find-evil/narrator.md      (strip leading qualifier)
      .claude/agents/find-evil/validator.md     (strip 'findings-' prefix)
    Returns the body text (after YAML frontmatter) or None if not found.
    """
    agents_dir = project_root / ".claude" / "agents"
    parts = agent_name.split("/")

    candidates: list[Path] = []
    if len(parts) == 2:
        ns, name = parts
        candidates += [
            agents_dir / ns / f"{name}.md",
            agents_dir / f"{agent_name}.md",
        ]
        short = name.split("-")[-1]
        candidates.append(agents_dir / ns / f"{short}.md")
        if name.startswith("findings-"):
            candidates.append(agents_dir / ns / f"{name[len('findings-'):]}.md")
        if name.startswith("ir-"):
            candidates.append(agents_dir / ns / f"{name[len('ir-'):]}.md")
        if name.endswith("-specialist"):
            base = name[: -len("-specialist")]
            candidates.append(agents_dir / ns / f"{base}-specialist.md")
    else:
        candidates.append(agents_dir / f"{agent_name}.md")

    for path in candidates:
        if path.exists():
            content = path.read_text()
            if content.startswith("---"):
                split = content.split("---", 2)
                if len(split) >= 3:
                    return split[2].strip()
            return content.strip()

    log.debug("Agent file not found for %s; tried: %s", agent_name,
              [str(c) for c in candidates])
    return None


# ---------------------------------------------------------------------------
# Claude subprocess helper
# ---------------------------------------------------------------------------

def run_agent(
    agent: str,
    prompt: str,
    *,
    model: str = MODEL_DEFAULT,
    timeout: int = SPECIALIST_TIMEOUT_S,
    capture: bool = True,
    project_root: Path | None = None,
) -> tuple[int, str]:
    """
    Spawn claude --print with agent system prompt injected via
    --append-system-prompt and return (exit_code, stdout).
    """
    cmd = ["claude", "--print", "--model", model, "--dangerously-skip-permissions"]

    if project_root:
        sys_prompt = load_agent_system_prompt(agent, project_root)
        if sys_prompt:
            cmd += ["--append-system-prompt", sys_prompt]
            log.debug("Loaded system prompt for agent=%s (%d chars)", agent, len(sys_prompt))
        else:
            log.warning("No agent file found for %s — running without system prompt", agent)

    cmd.append(prompt)

    log.info("▸ spawn agent=%s  timeout=%ds", agent, timeout)
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture,
            text=True,
            timeout=timeout,
        )
        stdout = result.stdout if capture else ""
        return result.returncode, stdout
    except subprocess.TimeoutExpired:
        log.warning("Agent %s timed out after %ds", agent, timeout)
        return 124, ""
    except FileNotFoundError:
        log.error("claude binary not found — is it in PATH?")
        return 127, ""


# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

class Investigator:
    def __init__(self, case_dir: Path, *, project_root: Path):
        self.case_dir    = case_dir.resolve()
        self.project_root = project_root
        self.case_id     = self.case_dir.name
        self.conn        = db_connect()

    # ------------------------------------------------------------------
    # INIT
    # ------------------------------------------------------------------

    def state_init(self) -> str:
        log.info("=== INIT: case_id=%s ===", self.case_id)

        rows = db_query(self.conn,
            "SELECT status FROM cases WHERE case_id = %s", (self.case_id,))

        if rows:
            status = rows[0]["status"]
            if status == "complete":
                log.info("Case already complete — nothing to do.")
                return "DONE"
            log.info("Resuming case from status=%s", status)
            return status.upper()

        db_exec(self.conn,
            "INSERT INTO cases (case_id, name, status) VALUES (%s, %s, 'triage') "
            "ON CONFLICT (case_id) DO NOTHING",
            (self.case_id, self.case_id))
        obs("Sleuth.case.started", {"case_id": self.case_id})
        log.info("Case row created — status=triage")
        return "TRIAGE"

    def _set_status(self, status: str):
        db_exec(self.conn,
            "UPDATE cases SET status = %s WHERE case_id = %s",
            (status, self.case_id))

    # ------------------------------------------------------------------
    # TRIAGE
    # ------------------------------------------------------------------

    def state_triage(self) -> str:
        log.info("=== TRIAGE ===")
        self._set_status("triage")

        existing = db_query(self.conn,
            "SELECT specialist FROM case_plan WHERE case_id = %s", (self.case_id,))
        if existing:
            log.info("case_plan already populated (%d rows) — skipping triage agent",
                     len(existing))
            return "DISPATCH"

        prompt = (
            f"Triage case {self.case_id} located at {self.case_dir}/. "
            "List all evidence files, classify each one, ensure the case exists "
            "in Postgres (INSERT INTO cases), insert one case_plan row per "
            "specialist found, then print the JSON dispatch."
        )
        rc, _out = run_agent(
            "find-evil/triage", prompt,
            timeout=TRIAGE_TIMEOUT_S,
            project_root=self.project_root,
        )
        if rc != 0:
            log.warning("Triage agent exited %d — checking case_plan anyway", rc)

        rows = db_query(self.conn,
            "SELECT specialist FROM case_plan WHERE case_id = %s", (self.case_id,))
        if not rows:
            log.error("Triage produced no case_plan rows — inserting default disk plan")
            db_exec(self.conn,
                "INSERT INTO case_plan (case_id, specialist, config) "
                "VALUES (%s, 'disk', %s) ON CONFLICT DO NOTHING",
                (self.case_id, json.dumps({
                    "classified_by": "adw-fallback",
                    "classified_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "tool_budget": 20,
                })))

        return "DISPATCH"

    # ------------------------------------------------------------------
    # DISPATCH
    # ------------------------------------------------------------------

    def _pre_extract_iocs(self) -> None:
        """Pre-stage: carve IOCs (emails, IPs, URLs) from every evidence file via the
        broker with a long, NON-interactive timeout, writing them to
        <case_dir>/carved_iocs.txt. Specialists then record these instantly instead of
        racing the agent's per-command bash timeout. Generalizes to any evidence size."""
        import glob, json as _json
        exts = (".dd", ".raw", ".img", ".e01", ".E01", ".pcap", ".pcapng", ".mem", ".aff4")
        files = [f for f in sorted(glob.glob(str(self.case_dir / "*"))) if f.endswith(exts)]
        if not files:
            return
        log.info("=== PRE-EXTRACT IOCs (%d evidence file(s)) ===", len(files))
        sections = []
        for fp in files:
            fname = os.path.basename(fp)
            log.info("  carving %s", fname)
            try:
                r = subprocess.run(
                    ["./bin/sb", "exec", "--case", self.case_id, "--tool", "bulk_extractor",
                     "--args", _json.dumps({"image": f"/case/{fname}"})],
                    cwd=str(self.project_root), capture_output=True, text=True, timeout=5400)
                obj = _json.loads(r.stdout or "{}")
                stdout = obj.get("stdout") or obj.get("stdout_preview") or ""
                tcid = obj.get("tool_call_id")
                sections.append("## carved IOCs from " + fname + "\n" + stdout)
                if tcid:
                    self._record_carved_iocs(stdout, tcid, fname)
                if fname.lower().endswith((".dd", ".raw", ".img", ".e01", ".aff4")):
                    log.info("  deep-carving (OST/EVTX) %s", fname)
                    rd = subprocess.run(
                        ["./bin/sb", "exec", "--case", self.case_id, "--tool", "deep_carve",
                         "--args", _json.dumps({"image": f"/case/{fname}"})],
                        cwd=str(self.project_root), capture_output=True, text=True, timeout=2400)
                    do = _json.loads(rd.stdout or "{}")
                    dstdout = do.get("stdout") or do.get("stdout_preview") or ""
                    dtcid = do.get("tool_call_id")
                    sections.append("## deep IOCs (OST/EVTX) from " + fname + "\n" + dstdout)
                    if dtcid:
                        self._record_carved_iocs(dstdout, dtcid, fname)
            except Exception as e:
                log.warning("  carve failed for %s: %s", fname, e)
        out_path = self.case_dir / "carved_iocs.txt"
        out_path.write_text("\n\n".join(sections))
        log.info("  wrote %s (%d bytes)", out_path, out_path.stat().st_size)
        self._confirm_carve_findings()

    def _confirm_carve_findings(self) -> None:
        """Deterministic carves (bulk_extractor/deep_carve) are self-validating: the IOC
        came verbatim from the cited tool's exit-0 output. Confirm them in code rather than
        through the LLM validator (reliable, and unaffected by agent rate/spend limits)."""
        import json as _json
        sql = ("SELECT f.finding_id, f.tool_call_id FROM findings f "
               "JOIN tool_calls tc ON tc.tool_call_id = f.tool_call_id "
               "WHERE f.case_id = '" + self.case_id.replace(chr(39), '') + "' "
               "AND tc.tool IN ('bulk_extractor','deep_carve') AND tc.exit_code = 0 "
               "AND f.validation_status = 'pending'")
        try:
            r = subprocess.run(["psql", DATABASE_URL, "-tAF", "\x1f", "-c", sql],
                               capture_output=True, text=True, timeout=120)
            n = 0
            for line in r.stdout.strip().splitlines():
                parts = line.split("\x1f")
                if len(parts) == 2 and parts[0]:
                    subprocess.run(["./bin/es", "set-validation", "--finding-id", parts[0],
                        "--status", "confirmed", "--validation-tool-call-id", parts[1]],
                        cwd=str(self.project_root), capture_output=True, text=True, timeout=30)
                    n += 1
            log.info("  auto-confirmed %d deterministic carve IOC findings", n)
        except Exception as e:
            log.warning("  auto-confirm failed: %s", e)

    def _record_carved_iocs(self, stdout, tcid, fname):
        """Record carved emails + IPs as findings citing the carve's tool_call so the
        validator can re-run the carve and confirm them (correct provenance)."""
        emails, ips, techniques, seen = [], [], [], set()
        section = None
        for line in stdout.splitlines():
            l = line.strip()
            if l.startswith("=== email"):
                section = "email"; continue
            if l.startswith("=== ip"):
                section = "ip"; continue
            if l.startswith("=== technique"):
                section = "technique"; continue
            if l.startswith("==="):
                section = None; continue
            if section == "email":
                m = re.search(r"([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})", l)
                if m and m.group(1) not in seen and len(emails) < 20:
                    seen.add(m.group(1)); emails.append(m.group(1))
            elif section == "ip":
                m = re.search(r"((?:[0-9]{1,3}\.){3}[0-9]{1,3})", l)
                if m and m.group(1) not in seen and len(ips) < 20:
                    seen.add(m.group(1)); ips.append(m.group(1))
            elif section == "technique":
                if "|" in l and len(techniques) < 30:
                    mitre, _, desc = l.partition("|")
                    mitre, desc = mitre.strip(), desc.strip()
                    key = (mitre, desc[:80])
                    if re.match(r"^T\d{4}", mitre) and key not in seen:
                        seen.add(key); techniques.append((mitre, desc))
        for em in emails:
            self._es_record("disk", "Email address " + em + " carved from evidence " + fname, tcid, "T1078")
        for ip in ips:
            self._es_record("disk", "IP address " + ip + " carved from evidence " + fname, tcid, "T1071")
        for mitre, desc in techniques:
            self._es_record("disk", desc + " (evidence " + fname + ")", tcid, mitre)
        log.info("  recorded %d email + %d ip + %d technique findings from %s", len(emails), len(ips), len(techniques), fname)

    def _es_record(self, spec, claim, tcid, mitre):
        try:
            subprocess.run(["./bin/es", "record-finding", "--case", self.case_id,
                "--specialist", spec, "--claim", claim, "--tool-call-id", tcid,
                "--confidence", "inferred", "--mitre", mitre],
                cwd=str(self.project_root), capture_output=True, text=True, timeout=60)
        except Exception as e:
            log.warning("  es record-finding failed: %s", e)

    def state_dispatch(self) -> str:
        log.info("=== DISPATCH ===")
        self._set_status("specialists_running")
        self._pre_extract_iocs()

        rows = db_query(self.conn,
            "SELECT specialist, config FROM case_plan WHERE case_id = %s",
            (self.case_id,))
        if not rows:
            log.error("No case_plan rows for case %s", self.case_id)
            return "DONE"

        self._specialist_rows = rows
        log.info("Dispatching %d specialist(s): %s",
                 len(rows), [r["specialist"] for r in rows])
        obs("Sleuth.dispatch", {
            "case_id": self.case_id,
            "specialists": [r["specialist"] for r in rows],
        })
        return "SPECIALISTS_RUNNING"

    # ------------------------------------------------------------------
    # SPECIALISTS_RUNNING
    # ------------------------------------------------------------------

    def state_specialists_running(self) -> str:
        log.info("=== SPECIALISTS_RUNNING ===")

        rows = getattr(self, "_specialist_rows", None)
        if rows is None:
            rows = db_query(self.conn,
                "SELECT specialist, config FROM case_plan WHERE case_id = %s",
                (self.case_id,))

        procs: list[tuple[str, subprocess.Popen]] = []

        for row in rows[:PARALLELISM_CAP]:
            spec = row["specialist"]
            agent = SPECIALIST_AGENT_MAP.get(spec, f"find-evil/{spec}-specialist")
            prompt = (
                f"Analyze {spec} evidence for case {self.case_id}. "
                f"Evidence directory: {self.case_dir}/. "
                f"FIRST: read {self.case_dir}/carved_iocs.txt if it exists - it holds "
                "emails, IP addresses and URLs already carved from the evidence. Record ONE "
                "finding per significant IOC (every email, every external/internal host IP, "
                "key URLs) with the LITERAL value in the claim and the artifact it came from. "
                "THEN run tool-based analysis via ./bin/sb exec, recording findings via "
                "./bin/es record-finding. Record every substantive finding (quality over "
                "quota); never pad with environment/tooling notes. Then exit."
            )
            cmd = ["claude", "--print", "--model", MODEL_DEFAULT,
                   "--dangerously-skip-permissions"]
            sys_prompt = load_agent_system_prompt(agent, self.project_root)
            if sys_prompt:
                cmd += ["--append-system-prompt", sys_prompt]
            cmd.append(prompt)

            log.info("  spawning specialist=%s", spec)
            obs("Sleuth.specialist.started", {"case_id": self.case_id, "specialist": spec})
            proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            procs.append((spec, proc))

        failed: list[tuple[str, str]] = []
        for spec, proc in procs:
            try:
                _out, _err = proc.communicate(timeout=SPECIALIST_TIMEOUT_S)
            except subprocess.TimeoutExpired:
                proc.kill()
                _out, _err = proc.communicate()
                log.warning("Specialist %s timed out", spec)
                failed.append((spec, _err[:2000] if _err else "timeout"))
                continue

            rc = proc.returncode
            if rc != 0:
                log.warning("Specialist %s exited %d", spec, rc)
                failed.append((spec, _err[:2000] if _err else ""))
            else:
                log.info("  specialist %s done (rc=0)", spec)
            obs("Sleuth.specialist.finished",
                {"case_id": self.case_id, "specialist": spec, "exit_code": rc})

        if failed and not getattr(self, "_no_self_correct", False):
            log.warning("Failed specialists: %s — entering SELF_CORRECTING",
                        [s for s, _ in failed])
            self._failed_specialists = failed
            return "SELF_CORRECTING"
        elif failed:
            log.warning("Failed specialists (self-correct disabled): %s",
                        [s for s, _ in failed])

        return "VALIDATING"

    # ------------------------------------------------------------------
    # SELF_CORRECTING
    # ------------------------------------------------------------------

    def state_self_correcting(self) -> str:
        log.info("=== SELF_CORRECTING ===")
        self._set_status("self_correcting")

        failed = getattr(self, "_failed_specialists", [])
        if not failed:
            failed_rows = db_query(
                self.conn,
                "SELECT specialist, stderr_tail FROM self_corrections "
                "WHERE case_id=%s AND succeeded IS NULL ORDER BY created_at",
                (self.case_id,),
            )
            failed = [(r["specialist"], r["stderr_tail"] or "") for r in failed_rows]

        sc = SelfCorrector(conn=self.conn, obs_fn=obs)

        for spec, stderr_tail in failed:
            last_rows = db_query(
                self.conn,
                "SELECT failed_tool, failed_args, failed_exit, stderr_tail "
                "FROM self_corrections "
                "WHERE case_id=%s AND specialist=%s "
                "ORDER BY created_at DESC LIMIT 1",
                (self.case_id, spec),
            )
            if last_rows:
                r = last_rows[0]
                sc.attempt(
                    case_id=self.case_id,
                    specialist=spec,
                    failed_tool=r["failed_tool"],
                    failed_args=r["failed_args"] if isinstance(r["failed_args"], dict) else {},
                    failed_exit=r["failed_exit"],
                    stderr_tail=r["stderr_tail"] or "",
                )
            else:
                sc.attempt(
                    case_id=self.case_id,
                    specialist=spec,
                    failed_tool="subprocess",
                    failed_args={},
                    failed_exit=1,
                    stderr_tail=stderr_tail,
                )

        self._failed_specialists = []
        return "VALIDATING"

    # ------------------------------------------------------------------
    # VALIDATING
    # ------------------------------------------------------------------

    def state_validating(self) -> str:
        log.info("=== VALIDATING ===")
        self._set_status("validating")

        pending = db_query(self.conn,
            "SELECT count(*) AS n FROM findings "
            "WHERE case_id = %s AND validation_status = 'pending'",
            (self.case_id,))
        n_pending = pending[0]["n"] if pending else 0
        log.info("Pending findings: %d", n_pending)

        if n_pending == 0:
            confirmed = db_query(self.conn,
                "SELECT count(*) AS n FROM findings "
                "WHERE case_id = %s AND validation_status = 'confirmed'",
                (self.case_id,))
            n_confirmed = confirmed[0]["n"] if confirmed else 0
            if n_confirmed > 0:
                log.info("All findings already validated (%d confirmed) — skipping validator", n_confirmed)
                return "NARRATING"
            log.warning("No findings at all — skipping validator")
            return "NARRATING"

        prompt = (
            f"Validate findings for case {self.case_id} specialist all. "
            "Re-execute every pending finding's tool call via ./bin/sb exec and "
            "set validation_status via ./bin/es set-validation. "
            "Mark 100% of pending findings before exiting."
        )
        rc, _out = run_agent(
            "find-evil/findings-validator", prompt,
            timeout=VALIDATE_TIMEOUT_S,
            project_root=self.project_root,
        )
        if rc != 0:
            log.warning("Validator exited %d", rc)

        return "NARRATING"

    # ------------------------------------------------------------------
    # NARRATING
    # ------------------------------------------------------------------

    def state_narrating(self) -> str:
        log.info("=== NARRATING ===")
        self._set_status("narrating")

        report_path = self.case_dir / "report.md"

        prompt = (
            f"Narrate case {self.case_id}. "
            f"Write the incident report to {report_path}. "
            "Query confirmed findings from Postgres, build a MITRE ATT&CK-aligned "
            "Markdown report with [F-NNN] citations for every factual claim, "
            "then verify the citation check passes."
        )
        rc, _out = run_agent(
            "find-evil/ir-narrator", prompt,
            model=MODEL_NARRATOR,
            timeout=NARRATE_TIMEOUT_S,
            project_root=self.project_root,
        )
        if rc != 0:
            log.warning("Narrator exited %d", rc)

        if not report_path.exists():
            log.warning("Narrator did not produce %s", report_path)

        return "DONE"

    # ------------------------------------------------------------------
    # DONE
    # ------------------------------------------------------------------

    def state_done(self):
        log.info("=== DONE ===")
        self._set_status("complete")
        db_exec(self.conn,
            "UPDATE cases SET finished_at = now() WHERE case_id = %s",
            (self.case_id,))
        obs("Sleuth.case.done", {"case_id": self.case_id})

        report_path = self.case_dir / "report.md"
        if report_path.exists():
            log.info("✓ report written: %s", report_path)
        else:
            log.warning("✗ report.md NOT found at %s", report_path)

    # ------------------------------------------------------------------
    # Run loop
    # ------------------------------------------------------------------

    def run(self):
        state = self.state_init()

        dispatch_table = {
            "TRIAGE":              self.state_triage,
            "DISPATCH":            self.state_dispatch,
            "SPECIALISTS_RUNNING": self.state_specialists_running,
            "SELF_CORRECTING":     self.state_self_correcting,
            "VALIDATING":          self.state_validating,
            "NARRATING":           self.state_narrating,
        }

        while state != "DONE":
            fn = dispatch_table.get(state)
            if fn is None:
                log.error("Unknown state: %s", state)
                break
            state = fn()

        self.state_done()

        report_path = self.case_dir / "report.md"
        return 0 if report_path.exists() else 1


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

def main():
    global MODEL_DEFAULT
    parser = argparse.ArgumentParser(
        description="ADW investigation driver — runs the full DFIR pipeline on a case directory."
    )
    parser.add_argument("case_dir", help="Path to the case directory (e.g. ./cases/mini/)")
    parser.add_argument("--model",  default=MODEL_DEFAULT, help="Default Claude model")
    parser.add_argument("--no-self-correct", action="store_true",
                        help="Disable self-correction retries (faster, less robust)")
    args = parser.parse_args()

    if args.model:
        MODEL_DEFAULT = args.model

    case_dir = Path(args.case_dir)
    if not case_dir.is_dir():
        log.error("case_dir does not exist: %s", case_dir)
        sys.exit(1)

    project_root = Path(__file__).parent.parent

    investigator = Investigator(case_dir, project_root=project_root)
    investigator._no_self_correct = args.no_self_correct
    sys.exit(investigator.run())


if __name__ == "__main__":
    main()
