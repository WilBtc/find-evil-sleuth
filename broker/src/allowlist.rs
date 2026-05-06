//! Tool allowlist + spec lookup.
//!
//! Uses runtime sqlx queries (no `query_as!` macros) so the workspace builds
//! against a clone with no live database — judges should be able to
//! `cargo build --release` without a DATABASE_URL.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{FromRow, PgPool};

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
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

const SELECT_COLS: &str = "tool, image, args_schema, timeout_s, memory_mb, pids_limit, network, seccomp_profile";

pub async fn list(pool: &PgPool) -> Result<Vec<ToolSpec>> {
    let sql = format!("SELECT {SELECT_COLS} FROM tool_specs ORDER BY tool");
    let rows = sqlx::query_as::<_, ToolSpec>(&sql).fetch_all(pool).await?;
    Ok(rows)
}

pub async fn get(pool: &PgPool, tool: &str) -> Result<Option<ToolSpec>> {
    let sql = format!("SELECT {SELECT_COLS} FROM tool_specs WHERE tool = $1");
    let row = sqlx::query_as::<_, ToolSpec>(&sql)
        .bind(tool)
        .fetch_optional(pool)
        .await?;
    Ok(row)
}
