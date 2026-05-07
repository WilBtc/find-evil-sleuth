# find-evil-sleuth

> Autonomous DFIR system for the SANS "FIND EVIL!" hackathon.
> Level-5 agentic architecture with architectural guardrails, Postgres substrate, and full SIFT toolchain.

## Architecture

![System Architecture](docs/architecture.svg)

The red dashed boundary marks the **architectural guardrail**: a Bash `PreToolUse` hook + Rust broker enforce that subagents can only invoke `./bin/sb` (sleuth-broker) and `./bin/es` (evidence-store). No raw shell access. No escape path.

See [plans/00-master-plan.md](plans/00-master-plan.md) for full design rationale.

## Quick Start

```bash
git clone http://localhost:3005/wil/find-evil-sleuth
cd find-evil-sleuth
docker compose -f docker/compose.yaml up -d
./scripts/investigate.sh ./cases/lone-wolf/
# cite a finding
./bin/es cite F-001
```

## Plans

See [plans/](plans/) for phase-by-phase implementation details.

## License

Apache-2.0
