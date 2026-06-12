# Changelog

## v1.0.0 — 2026-06-12 (SANS FIND EVIL! submission)

First public release: an autonomous, tamper-evident DFIR system on the SANS SIFT
Workstation. From raw evidence to a cited report with no human in the loop.

### Highlights
- **Architectural guardrail** — a `PreToolUse` hook + Rust broker force every forensic
  tool call through a validated, rootless-podman, seccomp-sandboxed path recorded in Postgres.
- **Full SANS SIFT 2026-04-22** integration (`sift-full`), built from the official OVA.
- **Deterministic IOC + technique extraction** — pre-stage carves emails/IPs (bulk_extractor,
  streaming for E01) and OST/EVTX + anti-forensic/cloud techniques (`deep_carve`, native E01),
  auto-confirmed in code (no LLM dependency, rate-limit-resilient).
- **Independent accuracy benchmark** (`score_accuracy.py`) against external answer keys:
  100% of extractable IOCs on the Nitroba network case; surfaced two phantom IOCs in the keys.
- **Persistent SaaS inspector** — browse cases, findings, Merkle audit chain, and the attack graph.
- **Host guardrails** (earlyoom + loadguard + cgroup slice) so heavy carves can't wedge the host.

Generalizes to fresh, unseen evidence: native E01 handling, generic evidence globbing,
and no test-case answers baked into the agents.
