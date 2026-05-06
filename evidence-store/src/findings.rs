use anyhow::Result;
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

    // Globally monotonic F-NNN — finding_id is a global primary key.
    // Parse current maximum numeric suffix and add 1.
    let next_n: (i64,) = sqlx::query_as(
        r#"SELECT COALESCE(MAX(NULLIF(regexp_replace(finding_id,'\D','','g'),'')::bigint),0) + 1
             FROM findings"#,
    )
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
