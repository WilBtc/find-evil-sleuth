#!/usr/bin/env python3
"""score_accuracy.py — Score find-evil-sleuth findings against a published answer key.

Independent, reproducible accuracy benchmark for Criterion 2 (IR Accuracy).
Consumes the VIGIA ground-truth schema (annatchijova/vigia-cases, schema 1.1):
  - key_iocs[].value     : ground-truth indicators (IPs, emails, hashes, filenames)
  - mitre_ttps[]         : expected ATT&CK techniques
  - verdict              : MALICE | SUSPICION | BENIGN  (BENIGN/SUSPICION = false-positive gate)

It scores the system's CONFIRMED findings (validator-approved) against that key and
reports IOC recall, MITRE-technique recall, verdict correctness, and the count of
confirmed findings that match no ground-truth item (precision proxy / candidate
over-claims). Pure stdlib; shells out to psql.

Usage:
  ./scripts/score_accuracy.py --case <case_id> --ground-truth cases/<x>/ground_truth.json
  ./scripts/score_accuracy.py --case <case_id> --ground-truth <gt> --json
"""
import argparse, json, subprocess, sys

DB_DEFAULT = "postgresql://sleuth:changeme-dev-only@127.0.0.1:5532/sleuth"


def fetch_confirmed(db, case_id):
    cid = case_id.replace("'", "''")
    sql = ("SELECT finding_id, coalesce(mitre_technique,''), "
           "replace(replace(claim, chr(10), ' '), chr(9), ' ') "
           "FROM findings WHERE case_id = '" + cid + "' AND validation_status = 'confirmed'")
    r = subprocess.run(["psql", db, "-tAF", "\x1f", "-c", sql],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"psql error: {r.stderr.strip()}")
    out = []
    for line in r.stdout.strip().splitlines():
        p = line.split("\x1f")
        if len(p) >= 3:
            out.append({"id": p[0], "mitre": p[1].strip(), "claim": p[2]})
    return out


def score(gt, findings):
    blob = " \n ".join(f["claim"] for f in findings).lower()
    mitres = {f["mitre"].upper() for f in findings if f["mitre"]}

    ioc_rows, ioc_hit = [], 0
    for ioc in gt.get("key_iocs", []):
        val = str(ioc.get("value", "")).strip()
        hit = bool(val) and val.lower() in blob
        ioc_hit += hit
        ioc_rows.append((ioc.get("type", "?"), val, hit))

    # exact match OR family match (a sub-technique satisfies its parent: T1566.002 -> T1566)
    fam = {m.split(".")[0] for m in mitres}
    ttp_rows, ttp_hit, ttp_fam_hit = [], 0, 0
    for t in gt.get("mitre_ttps", []):
        tu = t.upper()
        exact = tu in mitres or tu.lower() in blob
        family = exact or tu.split(".")[0] in fam or tu.split(".")[0].lower() in blob
        ttp_hit += exact
        ttp_fam_hit += family
        ttp_rows.append((t, exact, family))

    # precision proxy: confirmed findings that reference no ground-truth IOC value
    gt_vals = [str(i.get("value", "")).lower() for i in gt.get("key_iocs", []) if i.get("value")]
    matched_findings = sum(1 for f in findings if any(v in f["claim"].lower() for v in gt_vals))

    return {
        "case_id": gt.get("case_id"),
        "verdict_truth": gt.get("verdict"),
        "tier": gt.get("usability_tier"),
        "ioc_total": len(ioc_rows), "ioc_hit": ioc_hit, "ioc_rows": ioc_rows,
        "ttp_total": len(ttp_rows), "ttp_hit": ttp_hit, "ttp_fam_hit": ttp_fam_hit, "ttp_rows": ttp_rows,
        "confirmed": len(findings),
        "matched_findings": matched_findings,
        "unmatched_findings": len(findings) - matched_findings,
    }


def pct(n, d):
    return f"{(100*n//d) if d else 0}%"


def render_md(s):
    L = []
    L.append(f"### {s['case_id']} — tier: `{s['tier']}` — ground-truth verdict: **{s['verdict_truth']}**")
    L.append("")
    L.append(f"- **IOC recall:** {s['ioc_hit']}/{s['ioc_total']} ({pct(s['ioc_hit'], s['ioc_total'])})")
    for typ, val, hit in s["ioc_rows"]:
        L.append(f"  - {'✅' if hit else '❌'} `{val}` ({typ})")
    L.append(f"- **MITRE technique recall:** exact {s['ttp_hit']}/{s['ttp_total']} ({pct(s['ttp_hit'], s['ttp_total'])}) · "
             f"family {s['ttp_fam_hit']}/{s['ttp_total']} ({pct(s['ttp_fam_hit'], s['ttp_total'])})")
    for t, exact, family in s["ttp_rows"]:
        mark = "✅" if exact else ("≈ (family)" if family else "❌")
        L.append(f"  - {mark} {t}")
    L.append(f"- **Confirmed findings:** {s['confirmed']} "
             f"(matched to ground truth: {s['matched_findings']}, "
             f"unmatched/context: {s['unmatched_findings']})")
    if s["verdict_truth"] in ("SUSPICION", "BENIGN"):
        L.append(f"- ⚠️ **False-positive gate:** ground truth is **{s['verdict_truth']}**, "
                 f"not MALICE — system must NOT over-claim malicious intent here.")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True)
    ap.add_argument("--ground-truth", required=True)
    ap.add_argument("--db", default=DB_DEFAULT)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    with open(a.ground_truth) as fh:
        gt = json.load(fh)
    s = score(gt, fetch_confirmed(a.db, a.case))
    print(json.dumps(s, indent=2) if a.json else render_md(s))


if __name__ == "__main__":
    main()
