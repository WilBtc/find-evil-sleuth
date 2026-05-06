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
mod worker;

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
    /// Set validation_status on a finding (confirmed | refuted | inconclusive | drift).
    SetValidation {
        #[arg(long, value_name = "FINDING_ID")] finding_id: String,
        #[arg(long, value_name = "STATUS")] status: String,
        #[arg(long, value_name = "UUID")] validation_tool_call_id: Option<uuid::Uuid>,
    },
    /// Print the audit trace for a finding (the criterion-5 killer command).
    Cite { finding_id: String },
    /// Background worker subcommands.
    Worker {
        /// Start the pgvector embedding worker (LISTEN/NOTIFY → Ollama).
        #[arg(long)]
        embeddings: bool,
    },
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
        Cmd::SetValidation { finding_id, status, validation_tool_call_id } => {
            findings::set_validation(&pool, &finding_id, &status, validation_tool_call_id).await?;
            println!("set {} → {}", finding_id, status);
        }
        Cmd::Cite { finding_id } => {
            let trace = cite::cite(&pool, &finding_id).await?;
            println!("{}", serde_json::to_string_pretty(&trace)?);
        }
        Cmd::Worker { embeddings } => {
            if embeddings {
                worker::run(pool).await?;
            } else {
                anyhow::bail!("specify at least one worker flag (e.g. --embeddings)");
            }
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
