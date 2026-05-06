use anyhow::{Context, Result};
use serde_json::Value;
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::env;
use uuid::Uuid;

pub async fn connect() -> Result<PgPool> {
    let url = env::var("DATABASE_URL").unwrap_or_else(|_| {
        let host = env::var("PG_HOST").unwrap_or_else(|_| "127.0.0.1".into());
        let port = env::var("PG_PORT").unwrap_or_else(|_| "5532".into());
        let db   = env::var("PG_DB").unwrap_or_else(|_| "sleuth".into());
        let user = env::var("PG_USER").unwrap_or_else(|_| "sleuth".into());
        let pw   = env::var("PG_PASSWORD").unwrap_or_else(|_| "changeme-dev-only".into());
        format!("postgres://{user}:{pw}@{host}:{port}/{db}")
    });
    PgPoolOptions::new().max_connections(8).connect(&url).await.context("postgres connect")
}

pub async fn record_tool_call_start(
    pool: &PgPool,
    case_id: &str,
    tool: &str,
    args: &Value,
    is_validation: bool,
) -> Result<Uuid> {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO tool_calls (tool_call_id, case_id, tool, args, is_validation)
           VALUES ($1, $2, $3, $4, $5)"#,
    )
    .bind(id)
    .bind(case_id)
    .bind(tool)
    .bind(args)
    .bind(is_validation)
    .execute(pool)
    .await?;
    Ok(id)
}

pub async fn record_tool_call_finish(
    pool: &PgPool,
    tool_call_id: Uuid,
    exit_code: i32,
    duration_ms: i32,
    stdout_hash: Option<&[u8]>,
    stderr_hash: Option<&[u8]>,
) -> Result<()> {
    // tool_calls is a TimescaleDB hypertable keyed on (started_at, tool_call_id),
    // so UPDATE-by-tool_call_id alone is allowed (the planner finds the row in
    // the latest chunk). Use a WHERE-ranged UPDATE to keep the planner happy on
    // older PG/Timescale versions.
    sqlx::query(
        r#"UPDATE tool_calls
              SET finished_at = now(),
                  exit_code   = $2,
                  duration_ms = $3,
                  stdout_hash = $4,
                  stderr_hash = $5
            WHERE tool_call_id = $1
              AND started_at >= now() - interval '1 day'"#,
    )
    .bind(tool_call_id)
    .bind(exit_code)
    .bind(duration_ms)
    .bind(stdout_hash)
    .bind(stderr_hash)
    .execute(pool)
    .await?;
    Ok(())
}
