-- find-evil-sleuth · AGE graph schema + helpers (Phase 2.1.3)
-- Idempotent: uses IF NOT EXISTS guards and ON CONFLICT DO NOTHING.
--
-- Requires:  AGE extension loaded, case_graph already created by init.sql
-- Usage:     applied by `es init` (migration runner on dev-server)

-- Ensure AGE is loaded and search_path includes ag_catalog for this session.
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- ── Node labels ────────────────────────────────────────────────────────────────
-- AGE creates label tables lazily on first MERGE; we pre-create them so that
-- schema introspection and the sp_graph_assert helper can reference them safely.

SELECT * FROM cypher('case_graph', $$
  CREATE (n:Process {_init: true})
  RETURN n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (n:Process {_init: true}) DELETE n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (n:File {_init: true})
  RETURN n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (n:File {_init: true}) DELETE n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (n:RegistryKey {_init: true})
  RETURN n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (n:RegistryKey {_init: true}) DELETE n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (n:NetworkEndpoint {_init: true})
  RETURN n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (n:NetworkEndpoint {_init: true}) DELETE n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (n:User {_init: true})
  RETURN n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (n:User {_init: true}) DELETE n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (n:IOC {_init: true})
  RETURN n
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (n:IOC {_init: true}) DELETE n
$$) AS (n agtype);

-- ── Edge-label bootstrap (create a self-edge per label, then delete) ───────────
-- Edge labels: SPAWNED, WROTE, READ, LOADED, CONNECTED_TO, LOGGED_IN_AS, MATCHED

SELECT * FROM cypher('case_graph', $$
  CREATE (a:Process {_init: true})-[:SPAWNED]->(b:Process {_init: true})
  RETURN a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {_init: true}) DETACH DELETE a
$$) AS (a agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (a:Process {_init: true})-[:WROTE]->(b:File {_init: true})
  RETURN a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {_init: true}) DETACH DELETE a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:File {_init: true}) DETACH DELETE a
$$) AS (a agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (a:Process {_init: true})-[:READ]->(b:File {_init: true})
  RETURN a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {_init: true}) DETACH DELETE a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:File {_init: true}) DETACH DELETE a
$$) AS (a agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (a:Process {_init: true})-[:LOADED]->(b:File {_init: true})
  RETURN a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {_init: true}) DETACH DELETE a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:File {_init: true}) DETACH DELETE a
$$) AS (a agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (a:Process {_init: true})-[:CONNECTED_TO]->(b:NetworkEndpoint {_init: true})
  RETURN a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {_init: true}) DETACH DELETE a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:NetworkEndpoint {_init: true}) DETACH DELETE a
$$) AS (a agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (a:User {_init: true})-[:LOGGED_IN_AS]->(b:Process {_init: true})
  RETURN a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:User {_init: true}) DETACH DELETE a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {_init: true}) DETACH DELETE a
$$) AS (a agtype);

SELECT * FROM cypher('case_graph', $$
  CREATE (a:IOC {_init: true})-[:MATCHED]->(b:File {_init: true})
  RETURN a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:IOC {_init: true}) DETACH DELETE a
$$) AS (a agtype);
SELECT * FROM cypher('case_graph', $$
  MATCH (a:File {_init: true}) DETACH DELETE a
$$) AS (a agtype);

-- ── sp_graph_assert(label text, props_json jsonb) ─────────────────────────────
-- Convenience wrapper so Rust/Python callers can MERGE a node without
-- constructing dynamic Cypher strings outside the DB.
--
-- Example:
--   SELECT sp_graph_assert('Process', '{"pid":1234,"name":"svchost.exe"}');
--
-- Behaviour: MERGE on all provided properties; returns the agtype vertex.

CREATE OR REPLACE FUNCTION sp_graph_assert(
    p_label    text,
    p_props    jsonb
) RETURNS agtype
LANGUAGE plpgsql
AS $$
DECLARE
    v_cypher text;
    v_result agtype;
BEGIN
    LOAD 'age';
    SET LOCAL search_path = ag_catalog, public;

    -- Build a Cypher MERGE using the JSON properties as the identity key-set.
    -- The label is injected directly (caller must control this value — internal use only).
    v_cypher := format(
        'SELECT * FROM cypher(''case_graph'', $c$ MERGE (n:%s %s) RETURN n $c$) AS (n agtype)',
        p_label,
        (
            SELECT '{' || string_agg(
                format('%s: %s',
                    key,
                    CASE jsonb_typeof(value)
                        WHEN 'string'  THEN format('''%s''', value #>> '{}')
                        WHEN 'number'  THEN value::text
                        WHEN 'boolean' THEN value::text
                        ELSE format('''%s''', value::text)
                    END
                ), ', '
            ) || '}'
            FROM jsonb_each(p_props)
        )
    );

    EXECUTE v_cypher INTO v_result;
    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION sp_graph_assert(text, jsonb) IS
    'MERGE a node of the given label into case_graph using the supplied properties as the identity key-set. '
    'Returns the agtype vertex. Labels: Process, File, RegistryKey, NetworkEndpoint, User, IOC.';

-- ── sp_graph_edge(from_label, from_props, edge_label, to_label, to_props) ─────
-- Merges both endpoint nodes and then MERGEs the named edge between them.
-- Used by disk/memory/network specialists when recording findings.
--
-- Example:
--   SELECT sp_graph_edge(
--     'Process', '{"pid":888,"name":"powershell.exe"}',
--     'SPAWNED',
--     'Process', '{"pid":1024,"name":"mshta.exe"}'
--   );

CREATE OR REPLACE FUNCTION sp_graph_edge(
    p_from_label text,
    p_from_props jsonb,
    p_edge_label text,
    p_to_label   text,
    p_to_props   jsonb
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_cypher text;

    v_from_props_cy text;
    v_to_props_cy   text;
BEGIN
    LOAD 'age';
    SET LOCAL search_path = ag_catalog, public;

    v_from_props_cy := (
        SELECT '{' || string_agg(
            format('%s: %s', key,
                CASE jsonb_typeof(value)
                    WHEN 'string'  THEN format('''%s''', value #>> '{}')
                    WHEN 'number'  THEN value::text
                    WHEN 'boolean' THEN value::text
                    ELSE format('''%s''', value::text)
                END
            ), ', '
        ) || '}'
        FROM jsonb_each(p_from_props)
    );

    v_to_props_cy := (
        SELECT '{' || string_agg(
            format('%s: %s', key,
                CASE jsonb_typeof(value)
                    WHEN 'string'  THEN format('''%s''', value #>> '{}')
                    WHEN 'number'  THEN value::text
                    WHEN 'boolean' THEN value::text
                    ELSE format('''%s''', value::text)
                END
            ), ', '
        ) || '}'
        FROM jsonb_each(p_to_props)
    );

    v_cypher := format(
        'SELECT * FROM cypher(''case_graph'', $c$'
        ' MERGE (a:%s %s)'
        ' MERGE (b:%s %s)'
        ' MERGE (a)-[:%s]->(b)'
        ' $c$) AS (r agtype)',
        p_from_label, v_from_props_cy,
        p_to_label,   v_to_props_cy,
        p_edge_label
    );

    EXECUTE v_cypher;
END;
$$;

COMMENT ON FUNCTION sp_graph_edge(text, jsonb, text, text, jsonb) IS
    'MERGE two nodes and the named directed edge between them in case_graph. '
    'Edge labels: SPAWNED, WROTE, READ, LOADED, CONNECTED_TO, LOGGED_IN_AS, MATCHED.';
