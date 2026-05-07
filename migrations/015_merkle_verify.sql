-- 015_merkle_verify.sql
-- Pure-SQL function that re-derives a Merkle root from its leaves and
-- returns whether it matches the stored root_hash.
--
-- The Merkle tree over tool_calls for a case is built as follows:
--   leaf  = sha256(stdout_hash || stderr_hash)   for every tool_call whose
--           started_at <= rolled_up_at, ordered by (started_at, tool_call_id)
--   root  = iteratively sha256(left || right) up the binary tree
--
-- Because pure SQL cannot do arbitrary-depth tree recursion efficiently we
-- compute the root via a running sha256 fold (order-preserving chain hash),
-- which matches what evidence-store/src/merkle.rs uses:
--   chain = sha256(chain || leaf)   starting from a zero-byte seed
-- This is the "sequential Merkle fold" — tamper-evident, order-sensitive.

CREATE OR REPLACE FUNCTION merkle_verify(p_root_id bigint)
RETURNS TABLE (
    root_id       bigint,
    case_id       text,
    rolled_up_at  timestamptz,
    stored_hash   text,
    derived_hash  text,
    leaf_count    int,
    ok            boolean
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_case_id      text;
    v_rolled_up_at timestamptz;
    v_stored_hash  bytea;
    v_leaf_count   int;
    v_chain        bytea := '\x'::bytea;  -- zero-length seed
    v_leaf         bytea;
    v_derived      bytea;
    rec            record;
BEGIN
    SELECT mr.case_id, mr.rolled_up_at, mr.root_hash, mr.leaf_count
      INTO v_case_id, v_rolled_up_at, v_stored_hash, v_leaf_count
      FROM merkle_roots mr
     WHERE mr.root_id = p_root_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'merkle_roots row % not found', p_root_id;
    END IF;

    FOR rec IN
        SELECT tc.stdout_hash, tc.stderr_hash
          FROM tool_calls tc
         WHERE tc.case_id = v_case_id
           AND tc.started_at <= v_rolled_up_at
         ORDER BY tc.started_at, tc.tool_call_id
    LOOP
        v_leaf  := digest(
                       coalesce(rec.stdout_hash, '\x'::bytea) ||
                       coalesce(rec.stderr_hash, '\x'::bytea),
                       'sha256'
                   );
        v_chain := digest(v_chain || v_leaf, 'sha256');
    END LOOP;

    v_derived := v_chain;

    RETURN QUERY SELECT
        p_root_id,
        v_case_id,
        v_rolled_up_at,
        encode(v_stored_hash, 'hex'),
        encode(v_derived,     'hex'),
        v_leaf_count,
        v_stored_hash = v_derived;
END;
$$;

COMMENT ON FUNCTION merkle_verify(bigint) IS
  'Re-derives the Merkle chain root for a merkle_roots row from raw '
  'tool_call hashes and returns whether it matches the stored value. '
  'A mismatch indicates tampering or data corruption.';
