use anyhow::{Context, Result};
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::env;

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

pub async fn sanity_check(pool: &PgPool) -> Result<()> {
    let required = [
        "cases", "case_plan", "tool_calls", "artifacts", "findings",
        "validation_runs", "self_corrections", "merkle_roots", "tool_specs",
    ];
    for tbl in required {
        let exists: (bool,) = sqlx::query_as(
            "SELECT EXISTS (SELECT 1 FROM information_schema.tables
                              WHERE table_schema='public' AND table_name=$1)"
        )
        .bind(tbl)
        .fetch_one(pool)
        .await?;
        anyhow::ensure!(exists.0, "missing required table: {tbl}");
    }
    Ok(())
}
