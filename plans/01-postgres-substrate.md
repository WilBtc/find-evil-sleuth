# 01 · Postgres Substrate

> One Postgres 17 instance is the agent's working memory, audit log, attack graph, vector store, and scheduler. This doc fixes schema and extension roles before any code is written.

## Image

`docker/postgres/Dockerfile` builds from `postgres:17-bookworm` and adds:

| Extension | Version pin | Source |
|---|---|---|
| pgvector | 0.8.0 | apt `postgresql-17-pgvector` |
| timescaledb | 2.17.x | timescaledb apt repo |
| apache_age | 1.5.0 | build from source against pg17 (no apt; pin commit) |
| pg_cron | 1.6.x | apt `postgresql-17-cron` |
| pg_partman | 5.1.x | apt `postgresql-17-partman` |
| pg_jsonschema | 0.3.x | build (rust) |
| pg_graphql | 1.5.x | apt `postgresql-17-pg-graphql` |
| pg_trgm | bundled | contrib |
| pgcrypto | bundled | contrib |
| pg_stat_statements | bundled | contrib |
| pgaudit | 17.0 | apt `postgresql-17-pgaudit` |

`shared_preload_libraries = 'pg_stat_statements,pg_cron,pgaudit,timescaledb'`. `cron.database_name = 'sleuth'`.

## Schema (init.sql)

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_partman;
CREATE EXTENSION IF NOT EXISTS pg_jsonschema;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- ── Cases ─────────────────────────────────────────────────────────────
CREATE TABLE cases (
    case_id        text PRIMARY KEY,                -- e.g. lonewolf-2026-05-12
    name           text NOT NULL,
    started_at     timestamptz NOT NULL DEFAULT now(),
    finished_at    timestamptz,
    status         text NOT NULL DEFAULT 'running'  -- running|complete|failed
);

CREATE TABLE case_plan (
    case_id        text REFERENCES cases ON DELETE CASCADE,
    specialist     text NOT NULL,                    -- disk|memory|network
    config         jsonb NOT NULL,                   -- e.g. {"os_profile":"Win10x64"}
    PRIMARY KEY (case_id, specialist)
);

-- ── Tool calls (hypertable) ───────────────────────────────────────────
CREATE TABLE tool_calls (
    tool_call_id   uuid NOT NULL DEFAULT gen_random_uuid(),
    case_id        text NOT NULL,
    started_at     timestamptz NOT NULL DEFAULT now(),
    finished_at    timestamptz,
    tool           text NOT NULL,                    -- vol3, tshark, ...
    args           jsonb NOT NULL,
    exit_code      int,
    duration_ms    int,
    stdout_hash    bytea,                            -- blake3
    stderr_hash    bytea,
    container_id   text,
    is_validation  boolean NOT NULL DEFAULT false,
    PRIMARY KEY (started_at, tool_call_id)           -- TS requires time in PK
);
SELECT create_hypertable('tool_calls','started_at', chunk_time_interval => interval '1 day');

-- ── Artifacts (content-addressed) ─────────────────────────────────────
CREATE TABLE artifacts (
    artifact_hash  bytea PRIMARY KEY,                -- blake3, 32 bytes
    size_bytes     bigint NOT NULL,
    mime           text,
    blob_path      text NOT NULL,                    -- /var/sleuth/blobs/aa/bb/<hex>
    created_at     timestamptz NOT NULL DEFAULT now()
);

-- ── Findings ──────────────────────────────────────────────────────────
CREATE TABLE findings (
    finding_id        text PRIMARY KEY,              -- F-001, F-002 ...
    case_id           text REFERENCES cases ON DELETE CASCADE,
    specialist        text NOT NULL,
    claim             text NOT NULL,
    tool_call_id      uuid NOT NULL,                 -- FK enforced via trigger (TS hypertable)
    artifact_hash     bytea REFERENCES artifacts,
    byte_offset       bigint,
    confidence        text NOT NULL DEFAULT 'inferred',  -- confirmed|partial|inferred
    validation_status text NOT NULL DEFAULT 'pending',   -- pending|confirmed|refuted|inconclusive|drift
    last_validated_at timestamptz,
    superseded_by     text REFERENCES findings,
    created_at        timestamptz NOT NULL DEFAULT now(),
    embedding         vector(1536),
    mitre_technique   text                          -- T1059.001 etc
);
CREATE INDEX ON findings USING ivfflat (embedding vector_cosine_ops) WITH (lists=100);
CREATE INDEX ON findings (case_id, validation_status);
CREATE INDEX ON findings USING gin (claim gin_trgm_ops);

-- ── Validation runs ───────────────────────────────────────────────────
CREATE TABLE validation_runs (
    run_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    finding_id      text REFERENCES findings,
    started_at      timestamptz NOT NULL DEFAULT now(),
    result          text,
    diff            jsonb
);

-- ── Self-correction attempts ──────────────────────────────────────────
CREATE TABLE self_corrections (
    attempt_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id         text REFERENCES cases,
    specialist      text NOT NULL,
    failed_tool     text NOT NULL,
    failed_args     jsonb NOT NULL,
    failed_exit     int NOT NULL,
    stderr_tail     text,
    retry_strategy  text NOT NULL,                  -- 'derive_profile','editcap_recover',...
    retry_tool      text NOT NULL,
    retry_args      jsonb NOT NULL,
    succeeded       boolean,
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- ── Merkle audit chain ────────────────────────────────────────────────
CREATE TABLE merkle_roots (
    root_id         bigserial PRIMARY KEY,
    case_id         text REFERENCES cases,
    rolled_up_at    timestamptz NOT NULL DEFAULT now(),
    prev_root       bytea,
    root_hash       bytea NOT NULL,
    leaf_count      int NOT NULL
);

-- ── Tool schemas (used by broker via pg_jsonschema) ──────────────────
CREATE TABLE tool_specs (
    tool            text PRIMARY KEY,
    image           text NOT NULL,                  -- podman image ref
    args_schema     jsonb NOT NULL,                 -- JSON Schema draft 2020-12
    timeout_s       int NOT NULL DEFAULT 600,
    memory_mb       int NOT NULL DEFAULT 4096,
    pids_limit      int NOT NULL DEFAULT 256,
    network         text NOT NULL DEFAULT 'none',   -- none|host (host only for live cases)
    seccomp_profile text NOT NULL DEFAULT 'default'
);

-- ── AGE graph ─────────────────────────────────────────────────────────
SELECT create_graph('case_graph');
-- nodes: Process, File, RegistryKey, NetworkEndpoint, User, IOC
-- edges: SPAWNED, WROTE, READ, LOADED, CONNECTED_TO, LOGGED_IN_AS, MATCHED
```

## pg_cron jobs

```sql
SELECT cron.schedule('revalidate-findings', '*/30 * * * *', $$
  INSERT INTO validation_queue (finding_id)
  SELECT finding_id FROM findings
  WHERE validation_status = 'pending'
     OR (last_validated_at < now() - interval '1 hour'
         AND validation_status IN ('confirmed','partial'));
$$);

SELECT cron.schedule('merkle-rollup', '0 * * * *', $$
  CALL sp_merkle_rollup();   -- hashes new tool_calls into next root
$$);

SELECT cron.schedule('vacuum-hypertables', '0 3 * * *', $$
  VACUUM (ANALYZE) tool_calls;
$$);
```

## pgaudit configuration

`pgaudit.log = 'write,ddl'`. Output goes to Postgres logs collected by docker compose; treated as tamper-evident audit. Bundle `audit-<case_id>.log` into `submission/`.

## pgvector usage

- One embedding per finding's `claim` text (Ollama nomic-embed-text on g1-avilion, 768 → padded/projected to 1536, OR use `claude --print` to call a small embed model). Dim chosen to leave headroom.
- `WHERE embedding <=> $1 < 0.08 ORDER BY embedding <=> $1 LIMIT 5` — nearest existing finding; if cosine distance < 0.08 mark `superseded_by` and skip.

## AGE graph patterns used by narrator

```cypher
MATCH (p:Process {pid:$pid})-[:SPAWNED*1..3]->(child:Process)
RETURN child
```
```cypher
MATCH (p:Process)-[:CONNECTED_TO]->(e:NetworkEndpoint {ip:$ip})
RETURN p, e
```
```cypher
MATCH path=(u:User)-[:LOGGED_IN_AS]->(:Process)-[:WROTE]->(f:File {path:$path})
RETURN path
```

## partman partitioning

Only `tool_calls` (already a hypertable, partman not used) and `validation_runs` (partman daily). Avoids partman + timescale conflict.

## Backup before video day

Before recording: `pg_dump -Fc sleuth > submission/sleuth-pre-demo.dump`. Restore between takes if any take pollutes.
