use anyhow::{bail, Result};
use sqlx::PgPool;
use uuid::Uuid;

/// Allocate the next `F-NNN` id for a case and insert a finding row.
pub async fn record(
    pool: &PgPool,
    case_id: &str,
    specialist: &str,
    claim: &str,
    tool_call_id: Uuid,
    artifact_hash_hex: Option<&str>,
    byte_offset: Option<i64>,
    mitre: Option<&str>,
    confidence: &str,
) -> Result<String> {
    let mut tx = pool.begin().await?;

    // Globally monotonic F-NNN — use a SEQUENCE so concurrent specialists
    // never collide on the same id (MAX+1 is not safe under concurrency).
    let next_n: (i64,) = sqlx::query_as("SELECT nextval('finding_seq')")
        .fetch_one(&mut *tx)
        .await?;
    let finding_id = format!("F-{:03}", next_n.0);

    let artifact_bytes: Option<Vec<u8>> = match artifact_hash_hex {
        Some(s) => Some(hex::decode(s.trim_start_matches("blake3:"))?),
        None => None,
    };

    sqlx::query(
        r#"INSERT INTO findings
              (finding_id, case_id, specialist, claim, tool_call_id,
               artifact_hash, byte_offset, mitre_technique, confidence)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)"#,
    )
    .bind(&finding_id)
    .bind(case_id)
    .bind(specialist)
    .bind(claim)
    .bind(tool_call_id)
    .bind(artifact_bytes)
    .bind(byte_offset)
    .bind(mitre)
    .bind(confidence)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    sqlx::query("SELECT pg_notify('embed_findings', $1)")
        .bind(&finding_id)
        .execute(pool)
        .await?;

    Ok(finding_id)
}

/// Update `validation_status` and `last_validated_at` on an existing finding,
/// and append an immutable row to `validation_history`.
///
/// `status` must be one of: confirmed | refuted | inconclusive | drift.
/// `validation_tool_call_id` is the broker call UUID that was used to re-run the
/// original tool; it can be None when the validator makes the determination
/// without a re-execution (e.g. inconclusive due to missing evidence).
pub async fn set_validation(
    pool: &PgPool,
    finding_id: &str,
    status: &str,
    validation_tool_call_id: Option<Uuid>,
) -> Result<()> {
    match status {
        "confirmed" | "refuted" | "inconclusive" | "drift" => {}
        other => bail!("invalid validation status {:?}; must be confirmed|refuted|inconclusive|drift", other),
    }

    let mut tx = pool.begin().await?;

    let rows = sqlx::query(
        r#"UPDATE findings
              SET validation_status         = $2,
                  last_validated_at         = now(),
                  validation_tool_call_id   = COALESCE($3, validation_tool_call_id)
            WHERE finding_id               = $1"#,
    )
    .bind(finding_id)
    .bind(status)
    .bind(validation_tool_call_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();

    if rows == 0 {
        bail!("finding {} not found", finding_id);
    }

    sqlx::query(
        r#"INSERT INTO validation_history (finding_id, status, validation_tool_call_id)
           VALUES ($1, $2, $3)"#,
    )
    .bind(finding_id)
    .bind(status)
    .bind(validation_tool_call_id)
    .execute(&mut *tx)
    .await?;

    if let Some(tc_id) = validation_tool_call_id {
        sqlx::query(
            r#"UPDATE tool_calls SET is_validation = true WHERE tool_call_id = $1"#,
        )
        .bind(tc_id)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;

    Ok(())
}
