# Security Policy

find-evil-sleuth processes untrusted forensic evidence. The design assumption is that
**evidence is hostile**: every tool runs in a rootless podman container with a custom
seccomp profile, a read-only evidence mount, no network, and CPU/memory/pids limits.
Agents cannot reach a raw shell — a `PreToolUse` hook blocks anything but `./bin/sb`/`./bin/es`.

## Reporting a vulnerability
Please report security issues privately via GitHub Security Advisories
("Report a vulnerability" on the Security tab) rather than a public issue.
We aim to acknowledge within 72 hours.

## Scope of interest
- Sandbox escapes from the tool containers
- Argument-injection past `pg_jsonschema` validation in the broker
- Anything that lets an agent issue an unaudited tool call
- Tamper paths around the BLAKE3 / Merkle audit chain
