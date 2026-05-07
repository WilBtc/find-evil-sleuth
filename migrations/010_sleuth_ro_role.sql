-- find-evil-sleuth · create sleuth_ro read-only role (Phase 3.2.5)
-- The ir-narrator agent must connect with this role so that accidental
-- INSERT/UPDATE/DELETE from the narrator's connection is rejected by PG.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sleuth_ro') THEN
        CREATE ROLE sleuth_ro NOLOGIN;
    END IF;
END
$$;

-- Grant connect + usage on the database/schema
GRANT CONNECT ON DATABASE sleuth TO sleuth_ro;
GRANT USAGE ON SCHEMA public TO sleuth_ro;

-- SELECT-only on the tables the narrator needs to read
GRANT SELECT ON TABLE
    cases,
    findings,
    tool_calls,
    validation_history,
    artifacts
TO sleuth_ro;

-- Create a login user that wraps the role (needed for psql connection string)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sleuth_ro_user') THEN
        CREATE USER sleuth_ro_user WITH PASSWORD 'changeme-ro-dev-only';
    END IF;
END
$$;

GRANT sleuth_ro TO sleuth_ro_user;
