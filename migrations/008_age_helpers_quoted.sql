-- find-evil-sleuth · AGE Cypher injection fix (Phase 3.2.1)
-- Drops and re-creates sp_graph_assert and sp_graph_edge with:
--   1. Key name validation: only ^[A-Za-z_][A-Za-z0-9_]*$ allowed
--   2. String value quoting via Cypher-safe escaping:
--      backslashes → \\ first, then single quotes → \'
--      (AGE Cypher uses backslash escaping inside single-quoted strings)
--
-- Idempotent: DROP ... IF EXISTS + CREATE OR REPLACE

LOAD 'age';
SET search_path = ag_catalog, "$user", public;

DROP FUNCTION IF EXISTS sp_props_to_cypher(jsonb);
DROP FUNCTION IF EXISTS sp_graph_assert(text, jsonb);
DROP FUNCTION IF EXISTS sp_graph_edge(text, jsonb, text, jsonb, jsonb);
DROP FUNCTION IF EXISTS sp_graph_edge(text, jsonb, text, text, jsonb);

-- ── sp_cypher_str(v text) → text ────────────────────────────────────────────
-- Escape a text value for embedding in an AGE Cypher single-quoted string.
-- 1. Escape backslashes: \  →  \\
-- 2. Escape single quotes: '  →  \'
-- 3. Wrap in single quotes.
-- Result: 'bob\'s file.exe'  (valid Cypher literal)

CREATE OR REPLACE FUNCTION sp_cypher_str(v text)
RETURNS text
LANGUAGE sql
IMMUTABLE STRICT
AS $$
    SELECT '''' || replace(replace(v, '\', '\\'), '''', '\''') || ''''
$$;

COMMENT ON FUNCTION sp_cypher_str(text) IS
    'Escape a text value as a safe AGE Cypher single-quoted string literal. '
    'Escapes backslashes then single quotes.';

-- ── sp_props_to_cypher(props jsonb) → text ──────────────────────────────────
-- Converts a jsonb object to an AGE Cypher property map literal.
-- Keys are validated against ^[A-Za-z_][A-Za-z0-9_]*$.
-- String values are escaped via sp_cypher_str().
-- Returns e.g.  {name: 'bob\'s file.exe', pid: 1234}

CREATE OR REPLACE FUNCTION sp_props_to_cypher(p_props jsonb)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_key   text;
    v_parts text[] := '{}';
BEGIN
    FOR v_key IN
        SELECT key FROM jsonb_each(p_props)
    LOOP
        IF v_key !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'sp_props_to_cypher: unsafe property key %', v_key;
        END IF;

        v_parts := v_parts || (
            v_key || ': ' ||
            CASE jsonb_typeof(p_props->v_key)
                WHEN 'string'  THEN sp_cypher_str(p_props->>v_key)
                WHEN 'number'  THEN (p_props->v_key)::text
                WHEN 'boolean' THEN (p_props->v_key)::text
                ELSE sp_cypher_str((p_props->v_key)::text)
            END
        );
    END LOOP;

    RETURN '{' || array_to_string(v_parts, ', ') || '}';
END;
$$;

COMMENT ON FUNCTION sp_props_to_cypher(jsonb) IS
    'Convert a jsonb object to an AGE Cypher property-map literal. '
    'Keys must match ^[A-Za-z_][A-Za-z0-9_]*$; string values are injection-safe.';

-- ── sp_graph_assert(label text, props_json jsonb) ───────────────────────────
-- Convenience wrapper so Rust/Python callers can MERGE a node without
-- constructing dynamic Cypher strings outside the DB.
--
-- Example:
--   SELECT sp_graph_assert('Process', '{"pid":1234,"name":"svchost.exe"}');
--   SELECT sp_graph_assert('File', '{"name":"bob''s file.exe"}');
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

    IF p_label !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
        RAISE EXCEPTION 'sp_graph_assert: unsafe label %', p_label;
    END IF;

    v_cypher := format(
        'SELECT * FROM cypher(''case_graph'', $c$ MERGE (n:%s %s) RETURN n $c$) AS (n agtype)',
        p_label,
        sp_props_to_cypher(p_props)
    );

    EXECUTE v_cypher INTO v_result;
    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION sp_graph_assert(text, jsonb) IS
    'MERGE a node of the given label into case_graph using the supplied properties as the identity key-set. '
    'Returns the agtype vertex. Labels: Process, File, RegistryKey, NetworkEndpoint, User, IOC. '
    'Property keys must match ^[A-Za-z_][A-Za-z0-9_]*$; string values are injection-safe.';

-- ── sp_graph_edge(from_label, from_props, edge_label, to_label, to_props) ───
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
BEGIN
    LOAD 'age';
    SET LOCAL search_path = ag_catalog, public;

    IF p_from_label !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
        RAISE EXCEPTION 'sp_graph_edge: unsafe from_label %', p_from_label;
    END IF;
    IF p_edge_label !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
        RAISE EXCEPTION 'sp_graph_edge: unsafe edge_label %', p_edge_label;
    END IF;
    IF p_to_label !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
        RAISE EXCEPTION 'sp_graph_edge: unsafe to_label %', p_to_label;
    END IF;

    v_cypher := format(
        'SELECT * FROM cypher(''case_graph'', $c$'
        ' MERGE (a:%s %s)'
        ' MERGE (b:%s %s)'
        ' MERGE (a)-[:%s]->(b)'
        ' $c$) AS (r agtype)',
        p_from_label, sp_props_to_cypher(p_from_props),
        p_to_label,   sp_props_to_cypher(p_to_props),
        p_edge_label
    );

    EXECUTE v_cypher;
END;
$$;

COMMENT ON FUNCTION sp_graph_edge(text, jsonb, text, text, jsonb) IS
    'MERGE two nodes and the named directed edge between them in case_graph. '
    'Edge labels: SPAWNED, WROTE, READ, LOADED, CONNECTED_TO, LOGGED_IN_AS, MATCHED. '
    'All labels and property keys validated; string values are injection-safe.';
