# Postgres 16 + extensions for find-evil-sleuth
# We pinned to PG16 after verifying that Apache AGE upstream does not yet
# compile against PG17 (cypher_set.c calls index_beginscan with PG≤16 arity).
# Every other extension we use is well-supported on PG16, so this is the
# correct ship target. Bookworm base.
FROM postgres:16-bookworm

ARG PG_AGE_REF=PG16/v1.5.0
ARG PG_JSONSCHEMA_VER=0.3.3

ENV DEBIAN_FRONTEND=noninteractive

# ── Build deps + apt-managed extensions ──────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release \
        build-essential git \
        postgresql-server-dev-16 \
        flex bison \
        pkg-config libssl-dev \
        postgresql-16-cron \
        postgresql-16-partman \
        postgresql-16-pgaudit \
        postgresql-16-pgvector \
    && rm -rf /var/lib/apt/lists/*

# ── TimescaleDB (apt repo) ───────────────────────────────────────────────────
RUN curl -fsSL https://packagecloud.io/install/repositories/timescale/timescaledb/script.deb.sh | bash \
    && apt-get update && apt-get install -y --no-install-recommends \
        timescaledb-2-postgresql-16 \
    && rm -rf /var/lib/apt/lists/*

# ── Apache AGE (PG16 stable branch) ──────────────────────────────────────────
RUN git clone --depth 1 --branch ${PG_AGE_REF} https://github.com/apache/age.git /tmp/age \
    && cd /tmp/age \
    && make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config -j$(nproc) \
    && make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config install \
    && cd / && rm -rf /tmp/age

# ── pg_jsonschema (prebuilt for pg16; soft-fail if release missing) ─────────
RUN set -e; \
    if curl -fsSL -o /tmp/pgjs.deb \
        "https://github.com/supabase/pg_jsonschema/releases/download/v${PG_JSONSCHEMA_VER}/pg_jsonschema-v${PG_JSONSCHEMA_VER}-pg16-amd64-linux-gnu.deb" \
    ; then \
        dpkg -i /tmp/pgjs.deb && rm /tmp/pgjs.deb; \
    else \
        echo "pg_jsonschema prebuilt for pg16 not found at this version — extension is optional"; \
    fi

# ── Postgres tuning ──────────────────────────────────────────────────────────
RUN { \
        echo "shared_preload_libraries = 'pg_stat_statements,pg_cron,pgaudit,timescaledb'"; \
        echo "cron.database_name = 'sleuth'"; \
        echo "pgaudit.log = 'write,ddl'"; \
        echo "pg_stat_statements.track = 'all'"; \
    } >> /usr/share/postgresql/postgresql.conf.sample

# ── Init scripts run on first boot ───────────────────────────────────────────
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql

EXPOSE 5432
