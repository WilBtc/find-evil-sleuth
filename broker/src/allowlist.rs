use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolSpec {
    pub tool: String,
    pub image: String,
    pub args_schema: Value,
    pub timeout_s: i32,
    pub memory_mb: i32,
    pub pids_limit: i32,
    pub network: String,
    pub seccomp_profile: String,
}

pub async fn list(pool: &PgPool) -> Result<Vec<ToolSpec>> {
    let rows = sqlx::query_as!(
        ToolSpec,
        r#"SELECT tool, image, args_schema, timeout_s, memory_mb, pids_limit,
                  network, seccomp_profile
             FROM tool_specs ORDER BY tool"#,
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn get(pool: &PgPool, tool: &str) -> Result<Option<ToolSpec>> {
    let row = sqlx::query_as!(
        ToolSpec,
        r#"SELECT tool, image, args_schema, timeout_s, memory_mb, pids_limit,
                  network, seccomp_profile
             FROM tool_specs WHERE tool = $1"#,
        tool,
    )
    .fetch_optional(pool)
    .await?;
    Ok(row)
}
