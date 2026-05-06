//! `es cite F-NNN` — the criterion-5 audit-trail killer command.

use anyhow::{Context, Result};
use serde_json::{json, Value};
use sqlx::PgPool;

pub async fn cite(pool: &PgPool, finding_id: &str) -> Result<Value> {
    let row: Option<(String, String, String, String, sqlx::types::Uuid,
                     Option<Vec<u8>>, Option<i64>, String, String,
                     Option<String>, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        r#"SELECT finding_id, case_id, specialist, claim, tool_call_id,
                  artifact_hash, byte_offset, confidence, validation_status,
                  mitre_technique, created_at
             FROM findings WHERE finding_id = $1"#,
    )
    .bind(finding_id)
    .fetch_optional(pool)
    .await?;

    let (fid, case_id, specialist, claim, tool_call_id,
         artifact_hash, byte_offset, confidence, validation_status,
         mitre, created_at) = row.with_context(|| format!("finding {finding_id} not found"))?;

    let tc: Option<(sqlx::types::Uuid, String, Value, Option<i32>, Option<i32>,
                    chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        r#"SELECT tool_call_id, tool, args, exit_code, duration_ms, started_at
             FROM tool_calls WHERE tool_call_id = $1"#,
    )
    .bind(tool_call_id)
    .fetch_optional(pool)
    .await?;

    let validations: Vec<(chrono::DateTime<chrono::Utc>, Option<String>, Option<Value>)> =
        sqlx::query_as(
            r#"SELECT started_at, result, diff
                 FROM validation_runs WHERE finding_id = $1 ORDER BY started_at"#,
        )
        .bind(&fid)
        .fetch_all(pool)
        .await?;

    Ok(json!({
        "finding_id":         fid,
        "case_id":            case_id,
        "specialist":         specialist,
        "claim":              claim,
        "confidence":         confidence,
        "validation_status":  validation_status,
        "mitre_technique":    mitre,
        "created_at":         created_at,
        "tool_call": tc.map(|(id, tool, args, exit, dur, t)| json!({
            "id": id, "tool": tool, "args": args,
            "exit_code": exit, "duration_ms": dur, "started_at": t,
        })),
        "artifact": artifact_hash.map(|h| json!({
            "hash": format!("blake3:{}", hex::encode(h)),
            "byte_offset": byte_offset,
        })),
        "validation_history": validations.iter().map(|(at, r, d)|
            json!({"at": at, "result": r, "diff": d})
        ).collect::<Vec<_>>(),
    }))
}
