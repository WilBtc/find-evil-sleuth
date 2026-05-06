//! sleuth-broker (`sb`)
//!
//! Architectural guardrail: validates tool name + args, runs the tool inside a
//! rootless podman sandbox with seccomp, streams stdout/stderr to evidence-store,
//! returns a JSON receipt.
//!
//! Phase 1 status: scaffolding + describe/list-tools wired against Postgres.
//! Sandbox path lands in Phase 1.5.

mod db;
mod allowlist;
mod schema;
mod podman;
mod stream;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use serde_json::Value;
use std::env;

#[derive(Parser)]
#[command(name = "sb", version, about = "find-evil-sleuth tool broker")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    Exec {
        #[arg(long)]
        case: String,
        #[arg(long)]
        tool: String,
        #[arg(long)]
        args: String,
        #[arg(long)]
        validation: bool,
    },
    Describe { tool: String },
    ListTools,
}

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();
    let cli = Cli::parse();
    let pool = db::connect().await.context("connect to postgres")?;

    match cli.cmd {
        Cmd::ListTools => {
            for spec in allowlist::list(&pool).await? {
                println!("{:24} {}", spec.tool, spec.image);
            }
        }
        Cmd::Describe { tool } => {
            let spec = allowlist::get(&pool, &tool).await?
                .with_context(|| format!("tool not registered: {tool}"))?;
            println!("{}", serde_json::to_string_pretty(&spec)?);
        }
        Cmd::Exec { case, tool, args, validation } => {
            let parsed: Value = serde_json::from_str(&args).context("--args is not valid JSON")?;
            let receipt = exec(&pool, &case, &tool, parsed, validation).await?;
            println!("{}", serde_json::to_string_pretty(&receipt)?);
        }
    }
    Ok(())
}

async fn exec(
    pool: &sqlx::PgPool,
    case: &str,
    tool_name: &str,
    args: Value,
    validation: bool,
) -> Result<Value> {
    let spec = allowlist::get(pool, tool_name).await?
        .with_context(|| format!("tool not in allowlist: {tool_name}"))?;

    schema::validate(&spec.args_schema, &args)
        .context("args failed schema validation (broker rejected before exec)")?;

    let tool_call_id = db::record_tool_call_start(pool, case, tool_name, &args, validation).await?;
    db::record_tool_call_finish(pool, tool_call_id, 0, 0).await?;

    Ok(serde_json::json!({
        "tool_call_id": tool_call_id,
        "tool": tool_name,
        "case": case,
        "validation": validation,
        "status": "scaffolded",
        "note": "Phase 1 broker scaffold; podman sandbox path next."
    }))
}

fn init_tracing() {
    let level = env::var("RUST_LOG").unwrap_or_else(|_| "info".into());
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::new(level))
        .with_target(false).compact().init();
}
