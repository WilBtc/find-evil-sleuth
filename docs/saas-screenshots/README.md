# SaaS Inspector Screenshots

Screenshots captured from `./scripts/saas.sh up` (http://127.0.0.1:8932/).

| File | Screen |
|------|--------|
| `01-cases-list.png` | `/` — Case list with live status badges |
| `02-findings-table.png` | `/case/<id>/findings` — Findings table with confidence/status columns |
| `03-finding-drilldown.png` | `/finding/<fid>` — Single finding with tool call, artifact hash, MITRE tag |
| `04-audit-chain.png` | `/case/<id>/audit` — Merkle-chained audit trail with verify badge |
| `05-attack-graph.png` | `/case/<id>/graph` — vis-network AGE attack graph |

To regenerate: `./scripts/saas.sh up` then visit each URL.
