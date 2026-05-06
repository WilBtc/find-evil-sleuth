//! evidence-store (`es`)
//!
//! Single source of truth for findings, citations, AGE graph mutations,
//! pgvector ops, Merkle audit chain. Used by every subagent and the broker.
//!
//! Phase 1 status: `init`, `record-finding`, `cite` end-to-end against Postgres.
//! Worker (`es worker --embeddings`), graph passthrough, Merkle rollup land in Phase 2/3.

mod db;
mod findings;
mod cite;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::env;

#[derive(Parser)]
#[command(name = "es", version, about = "find-evil-sleuth evidence store")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Verify migrations applied and required tables exist.
    Init,
    /// Insert a finding row.
    RecordFinding {
        #[arg(long)] case: String,
        #[arg(long)] specialist: String,
        #[arg(long)] claim: String,
        #[arg(long, value_name = "UUID")] tool_call_id: uuid::Uuid,
        #[arg(long)] artifact_hash: Option<String>,
        #[arg(long)] byte_offset: Option<i64>,
        #[arg(long)] mitre: Option<String>,
        #[arg(long, default_value = "inferred")] confidence: String,
    },
    /// Print the audit trace for a finding (the criterion-5 killer command).
    Cite { finding_id: String },
}

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();
    let cli = Cli::parse();
    let pool = db::connect().await.context("connect to postgres")?;

    match cli.cmd {
        Cmd::Init => {
            db::sanity_check(&pool).await?;
            println!("evidence-store ready");
        }
        Cmd::RecordFinding {
            case, specialist, claim, tool_call_id,
            artifact_hash, byte_offset, mitre, confidence,
        } => {
            let id = findings::record(
                &pool, &case, &specialist, &claim,
                tool_call_id,
                artifact_hash.as_deref(),
                byte_offset,
                mitre.as_deref(),
                &confidence,
            ).await?;
            println!("{}", id);
        }
        Cmd::Cite { finding_id } => {
            let trace = cite::cite(&pool, &finding_id).await?;
            println!("{}", serde_json::to_string_pretty(&trace)?);
        }
    }
    Ok(())
}

fn init_tracing() {
    let level = env::var("RUST_LOG").unwrap_or_else(|_| "info".into());
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::new(level))
        .with_target(false).compact().init();
}
