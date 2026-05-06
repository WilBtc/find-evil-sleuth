# 03 · evidence-store (Rust)

> Rust binary `./bin/es`. Single source of truth for findings, citations, AGE graph mutations, pgvector ops, Merkle audit chain. Used by every subagent and by the broker.

## Subcommands

```
es init                              # idempotent migrations
es record-finding --case ... --specialist ... --claim '...' \
                  --tool-call-id <uuid> --artifact-hash blake3:... \
                  [--byte-offset N] [--mitre T1059.001]
es cite <finding-id>                 # full trace JSON for judges
es validate --finding <id> --result confirmed|refuted|inconclusive --diff '<json>'
es self-correct record --case ... --failed-tool ... --strategy ... ...
es search "<query>" [--top-k 5]      # pgvector knn over claims
es graph cypher '<query>'            # AGE passthrough
es get-bytes <hash> [--offset N --len N]
es merkle root <case>                # current root for case
es export --case <id> --to submission/case-<id>/   # NDJSON dump for Devpost
```

## `cite` output (the criterion-5 killer feature)

```json
{
  "finding_id": "F-042",
  "claim": "PowerShell process spawned mshta.exe with -url payload from suspicious_user.local",
  "confidence": "confirmed",
  "validation_status": "confirmed",
  "tool_call": {
    "id": "8b2c…",
    "tool": "vol3",
    "args": {"plugin":"windows.pstree","memory_image":"/case/memory/lonewolf.raw"},
    "started_at": "2026-05-22T19:08:14Z",
    "duration_ms": 18432,
    "exit_code": 0,
    "stdout_preview_first_4k": "…",
    "stdout_full": "es get-bytes blake3:… (cmd)"
  },
  "artifact": {
    "hash": "blake3:bc4e…",
    "size_bytes": 28411,
    "byte_offset": 14922
  },
  "graph_context": [
    {"path": "(p:Process {pid:5212,name:'powershell.exe'})-[:SPAWNED]->(c:Process {pid:7044,name:'mshta.exe'})"}
  ],
  "validation_history": [
    {"at":"2026-05-22T19:11:02Z","result":"confirmed","diff":null},
    {"at":"2026-05-22T20:11:02Z","result":"confirmed","diff":null}
  ],
  "mitre_technique": "T1218.005",
  "merkle_root_at_creation": "blake3:7a02…"
}
```

Judges run `./bin/es cite F-042` once. They get tool, args, hash, offset, graph context, validation history, MITRE technique, and the Merkle root that pinned the audit state when the finding was created. **No other submission will produce this.**

## Merkle chain

Per case, ordered by `tool_calls.started_at`. Leaves = blake3 of `(tool_call_id || stdout_hash || stderr_hash || exit_code)`. Hourly `pg_cron` runs `sp_merkle_rollup` which appends one root per case per hour, chained to the previous root. Tampering with any tool_call after the fact breaks the chain — verifiable by `es verify --case <id>`.

## Storage layout

```
/var/sleuth/
├── pg_data/                 # postgres volume
└── blobs/
    ├── aa/bb/aabb...hex     # 65535 leading dirs, ~64M files easy
    └── ...
```

Filesystem: ext4 + `chattr +i` after rollup hour to make tampering noisy. Backup target on insa-server-2 backup pool (existing 358-file IoT backup pool can host it; tag with `sleuth/`).

## pgvector embedding pipeline

1. New finding → `es record-finding` writes row, fires `NOTIFY embed_findings, '<finding_id>'`.
2. Background worker (also in evidence-store binary, `es worker --embeddings`) listens, batches every 5s, calls Ollama on g1-avilion (`http://100.116.33.91:11434/api/embed`) with `nomic-embed-text` model, writes 1536-dim (zero-padded from 768).
3. Same worker re-runs nearest-neighbor on insert: if `cosine_distance < 0.08`, sets `superseded_by` on the *new* row and skips it from narrator queries. Visible win for criterion 1 (autonomy: agent doesn't repeat itself across iterations).

## AGE graph mutations

`es record-finding` accepts an optional `--graph-cypher '<MERGE…>'` arg. Examples each specialist emits:

- disk: `MERGE (f:File {path:$path, sha256:$sha}) ON CREATE SET f.size=$size`
- memory: `MERGE (p:Process {pid:$pid, name:$name}) MERGE (parent:Process {pid:$ppid}) MERGE (parent)-[:SPAWNED]->(p)`
- network: `MERGE (e:NetworkEndpoint {ip:$ip,port:$port}) MERGE (p:Process {pid:$pid}) MERGE (p)-[:CONNECTED_TO {when:$ts}]->(e)`

Narrator queries combine across specialists — that's what makes the report a story instead of three lists.

## Crate map

```
evidence-store/
├── Cargo.toml         # tokio, sqlx, blake3, serde, clap, reqwest (Ollama)
└── src/
    ├── main.rs
    ├── db.rs          # pool + queries
    ├── findings.rs    # record / supersede / search
    ├── cite.rs        # the killer feature
    ├── merkle.rs      # rollup
    ├── graph.rs       # AGE passthrough
    ├── vector.rs      # ollama embed + ivfflat search
    ├── worker.rs      # NOTIFY/LISTEN embed worker
    └── http.rs        # :8931 minimal JSON over HTTP for hooks
```

Build: `cargo build --release` → `./bin/es`.
