# Contributing to find-evil-sleuth

Thanks for your interest! find-evil-sleuth is an autonomous DFIR system; contributions
that improve forensic accuracy, add SIFT tool integrations, or harden the broker are
especially welcome.

## Dev setup
```bash
git clone https://github.com/WilBtc/find-evil-sleuth
cd find-evil-sleuth
docker compose -f docker/compose.yaml up -d      # Postgres 17 substrate
cargo build --release                            # broker (sb), evidence-store (es), saas
./scripts/smoke-test.sh --skip-compose           # sanity check
```

## Architecture in one line
A Bash `PreToolUse` hook forces every agent tool call through `./bin/sb` (the Rust broker),
which validates args, sandboxes the tool in rootless podman, and records every call in
Postgres. See [`plans/`](plans/) for the full design and [`docs/OPS-GUARDRAILS.md`](docs/OPS-GUARDRAILS.md) for host limits.

## Adding a forensic tool
1. Register it in `migrations/0NN_<tool>.sql` (`tool_specs` row: image, args schema, limits).
2. Add an argv builder arm in `broker/src/podman.rs`.
3. Rebuild `sb`, run a `./bin/sb exec` smoke test.
4. If it's an IOC carver, wire it into the pre-extract stage in `adws/investigate.py`.

## Pull requests
- Keep changes focused; match the surrounding style.
- New forensic logic should be **deterministic where possible** (carve + auto-confirm) rather than agent-only — it's more reliable and not rate-limited.
- Run `./scripts/smoke-test.sh --skip-compose` before opening a PR.
- Never commit evidence images or secrets.

By contributing you agree your work is licensed under Apache-2.0.
