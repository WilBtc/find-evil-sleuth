-- find-evil-sleuth · Postgres bootstrap
-- Runs once on first container start. Idempotent against re-runs (CREATE … IF NOT EXISTS).
-- Schema reference: plans/01-postgres-substrate.md

\set ON_ERROR_STOP off
-- Optional extensions (continue on miss)
CREATE EXTENSION IF NOT EXISTS pg_jsonschema;
CREATE EXTENSION IF NOT EXISTS pg_graphql;
\set ON_ERROR_STOP on

-- Required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_partman;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';

-- AGE uses ag_catalog; keep public the default for our relational tables
SET search_path = public, ag_catalog, "$user";

-- ─────────────────────────────────────────────────────────────────────────────
-- Cases
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cases (
    case_id     text PRIMARY KEY,
    name        text NOT NULL,
    started_at  timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    status      text NOT NULL DEFAULT 'running'
);

CREATE TABLE IF NOT EXISTS case_plan (
    case_id    text REFERENCES cases ON DELETE CASCADE,
    specialist text NOT NULL,
    config     jsonb NOT NULL,
    PRIMARY KEY (case_id, specialist)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Tool calls (TimescaleDB hypertable)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tool_calls (
    tool_call_id  uuid NOT NULL DEFAULT gen_random_uuid(),
    case_id       text NOT NULL,
    started_at    timestamptz NOT NULL DEFAULT now(),
    finished_at   timestamptz,
    tool          text NOT NULL,
    args          jsonb NOT NULL,
    exit_code     int,
    duration_ms   int,
    stdout_hash   bytea,
    stderr_hash   bytea,
    container_id  text,
    is_validation boolean NOT NULL DEFAULT false,
    PRIMARY KEY (started_at, tool_call_id)
);

DO $$ BEGIN
    PERFORM create_hypertable('tool_calls','started_at',
                              chunk_time_interval => interval '1 day',
                              if_not_exists => TRUE);
EXCEPTION WHEN undefined_function THEN
    -- Timescale not loaded; degrade to plain table (CI / unit-test environments)
    NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Artifacts (content-addressed)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS artifacts (
    artifact_hash bytea PRIMARY KEY,
    size_bytes    bigint NOT NULL,
    mime          text,
    blob_path     text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Findings
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS findings (
    finding_id        text PRIMARY KEY,
    case_id           text REFERENCES cases ON DELETE CASCADE,
    specialist        text NOT NULL,
    claim             text NOT NULL,
    tool_call_id      uuid NOT NULL,
    artifact_hash     bytea REFERENCES artifacts,
    byte_offset       bigint,
    confidence        text NOT NULL DEFAULT 'inferred',
    validation_status text NOT NULL DEFAULT 'pending',
    last_validated_at timestamptz,
    superseded_by     text REFERENCES findings,
    created_at        timestamptz NOT NULL DEFAULT now(),
    embedding         vector(1536),
    mitre_technique   text
);
CREATE INDEX IF NOT EXISTS findings_embedding_idx
    ON findings USING ivfflat (embedding vector_cosine_ops) WITH (lists=100);
CREATE INDEX IF NOT EXISTS findings_case_status_idx
    ON findings (case_id, validation_status);
CREATE INDEX IF NOT EXISTS findings_claim_trgm_idx
    ON findings USING gin (claim gin_trgm_ops);

-- ─────────────────────────────────────────────────────────────────────────────
-- Validation runs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS validation_runs (
    run_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    finding_id text REFERENCES findings,
    started_at timestamptz NOT NULL DEFAULT now(),
    result     text,
    diff       jsonb
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Self-corrections
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS self_corrections (
    attempt_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id        text REFERENCES cases,
    specialist     text NOT NULL,
    failed_tool    text NOT NULL,
    failed_args    jsonb NOT NULL,
    failed_exit    int NOT NULL,
    stderr_tail    text,
    retry_strategy text NOT NULL,
    retry_tool     text NOT NULL,
    retry_args     jsonb NOT NULL,
    succeeded      boolean,
    created_at     timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Merkle audit roots
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS merkle_roots (
    root_id      bigserial PRIMARY KEY,
    case_id      text REFERENCES cases,
    rolled_up_at timestamptz NOT NULL DEFAULT now(),
    prev_root    bytea,
    root_hash    bytea NOT NULL,
    leaf_count   int NOT NULL
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Tool specs (consumed by sleuth-broker)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tool_specs (
    tool            text PRIMARY KEY,
    image           text NOT NULL,
    args_schema     jsonb NOT NULL,
    timeout_s       int NOT NULL DEFAULT 600,
    memory_mb       int NOT NULL DEFAULT 4096,
    pids_limit      int NOT NULL DEFAULT 256,
    network         text NOT NULL DEFAULT 'none',
    seccomp_profile text NOT NULL DEFAULT 'default'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- AGE graph
-- ─────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
    PERFORM create_graph('case_graph');
EXCEPTION WHEN duplicate_object THEN NULL; -- already exists
WHEN undefined_function THEN NULL;          -- AGE not loaded (CI fallback)
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- pg_cron jobs (no-op if no rows yet)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
    PERFORM cron.schedule('vacuum-tool-calls', '0 3 * * *',
                          'VACUUM (ANALYZE) tool_calls');
EXCEPTION WHEN undefined_table OR undefined_function THEN NULL;
END $$;
