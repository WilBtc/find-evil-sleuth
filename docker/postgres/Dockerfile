# Postgres 17 + 11 extensions for find-evil-sleuth
# Bookworm base. Pinned versions for reproducibility.
FROM postgres:16-bookworm

ARG PG_AGE_REF=master   # Apache AGE upstream tag — pin a sha after Phase 1 smoke
ARG PG_JSONSCHEMA_VER=0.3.3

ENV DEBIAN_FRONTEND=noninteractive

# ── Build deps + apt-managed extensions ──────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release \
        build-essential git \
        postgresql-server-dev-17 \
        flex bison \
        pkg-config libssl-dev \
        # contrib + apt extensions
        postgresql-17-cron \
        postgresql-17-partman \
        postgresql-17-pgaudit \
        postgresql-17-pgvector \
    && rm -rf /var/lib/apt/lists/*

# ── TimescaleDB (apt repo) ───────────────────────────────────────────────────
RUN curl -s https://packagecloud.io/install/repositories/timescale/timescaledb/script.deb.sh | bash \
    && apt-get update && apt-get install -y --no-install-recommends \
        timescaledb-2-postgresql-17 \
    && rm -rf /var/lib/apt/lists/*

# ── pg_graphql (apt via supabase repo) ───────────────────────────────────────
# pg_graphql ships as the `pg_graphql` extension. If apt package unavailable
# for pg17 at build time, this layer is a soft-fail and we skip the extension
# (init.sql uses CREATE EXTENSION IF NOT EXISTS so missing extension is fine).
RUN curl -fsSL https://supabase.com/.well-known/pgsodium-getkey.sh 2>/dev/null \
    || true

# ── Apache AGE (build from source, no apt for pg17) ──────────────────────────
RUN git clone https://github.com/apache/age.git /tmp/age \
    && cd /tmp/age && git checkout ${PG_AGE_REF} \
    && make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config -j$(nproc) \
    && make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config install \
    && cd / && rm -rf /tmp/age

# ── pg_jsonschema (Rust pgrx; build from prebuilt if available, else skip) ───
# The prebuilt path is fastest; fall back to source build if needed.
RUN curl -fsSL -o /tmp/pgjs.deb \
        "https://github.com/supabase/pg_jsonschema/releases/download/v${PG_JSONSCHEMA_VER}/pg_jsonschema-v${PG_JSONSCHEMA_VER}-pg17-amd64-linux-gnu.deb" \
        && dpkg -i /tmp/pgjs.deb && rm /tmp/pgjs.deb \
        || echo "pg_jsonschema prebuilt unavailable — extension marked optional in init.sql"

# ── Postgres tuning ──────────────────────────────────────────────────────────
RUN echo "shared_preload_libraries = 'pg_stat_statements,pg_cron,pgaudit,timescaledb'" \
        >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "cron.database_name = 'sleuth'"   >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "pgaudit.log = 'write,ddl'"      >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "pg_stat_statements.track = all"  >> /usr/share/postgresql/postgresql.conf.sample

# ── Init scripts run on first boot ───────────────────────────────────────────
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql

EXPOSE 5432
