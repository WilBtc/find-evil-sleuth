# Postgres 17 + extensions for find-evil-sleuth.
# AGE master does not compile against PG17 (cypher_set.c index_beginscan arity),
# but AGE has a dedicated `release/PG17/1.7.0` branch that does. Use it.
FROM postgres:17-bookworm

# Apache AGE branch known to compile against PG17 (release/PG17/1.7.0).
ARG PG_AGE_REF=release/PG17/1.7.0
ARG PG_JSONSCHEMA_VER=0.3.3

ENV DEBIAN_FRONTEND=noninteractive

# ── Build deps + apt-managed extensions ──────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release \
        build-essential git \
        postgresql-server-dev-17 \
        flex bison \
        pkg-config libssl-dev \
        postgresql-17-cron \
        postgresql-17-partman \
        postgresql-17-pgaudit \
        postgresql-17-pgvector \
    && rm -rf /var/lib/apt/lists/*

# ── TimescaleDB (apt repo) ───────────────────────────────────────────────────
RUN curl -fsSL https://packagecloud.io/install/repositories/timescale/timescaledb/script.deb.sh | bash \
    && apt-get update && apt-get install -y --no-install-recommends \
        timescaledb-2-postgresql-17 \
    && rm -rf /var/lib/apt/lists/*

# ── Apache AGE (PG17 release branch) ─────────────────────────────────────────
RUN git clone --depth 1 --branch ${PG_AGE_REF} https://github.com/apache/age.git /tmp/age \
    && cd /tmp/age \
    && make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config -j$(nproc) \
    && make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config install \
    && cd / && rm -rf /tmp/age

# ── pg_jsonschema (prebuilt; soft-fail if release missing for pg17) ──────────
RUN set -e; \
    if curl -fsSL -o /tmp/pgjs.deb \
        "https://github.com/supabase/pg_jsonschema/releases/download/v${PG_JSONSCHEMA_VER}/pg_jsonschema-v${PG_JSONSCHEMA_VER}-pg17-amd64-linux-gnu.deb" \
    ; then \
        dpkg -i /tmp/pgjs.deb && rm /tmp/pgjs.deb; \
    else \
        echo "pg_jsonschema prebuilt for pg17 not yet released — extension is optional"; \
    fi

# ── Postgres tuning ──────────────────────────────────────────────────────────
RUN { \
        echo "shared_preload_libraries = 'pg_stat_statements,pg_cron,pgaudit,timescaledb'"; \
        echo "cron.database_name = 'sleuth'"; \
        echo "pgaudit.log = 'write,ddl'"; \
        echo "pg_stat_statements.track = 'all'"; \
    } >> /usr/share/postgresql/postgresql.conf.sample

COPY init.sql /docker-entrypoint-initdb.d/01-init.sql

EXPOSE 5432
