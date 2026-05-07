//! sleuth-broker (`sb`)
//!
//! Architectural guardrail. Validates tool name + args, runs the tool inside a
//! rootless podman sandbox with seccomp, streams stdout/stderr through blake3
//! into the blob store, returns a JSON receipt.

mod db;
mod allowlist;
mod schema;
mod podman;
mod stream;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use serde_json::Value;
use std::env;
use std::path::PathBuf;

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
        /// Mark this run as a validator re-execution.
        #[arg(long)]
        validation: bool,
        /// Path to the case directory (read-only mounted into the sandbox).
        /// Defaults to ${SLEUTH_CASES_ROOT:-./cases}/<case>.
        #[arg(long)]
        case_dir: Option<PathBuf>,
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
        Cmd::Exec { case, tool, args, validation, case_dir } => {
            let parsed: Value = serde_json::from_str(&args)
                .context("--args is not valid JSON")?;
            let case_dir = case_dir.unwrap_or_else(|| {
                let root = env::var("SLEUTH_CASES_ROOT").unwrap_or_else(|_| "./cases".into());
                PathBuf::from(root).join(&case)
            });
            let scratch_root = env::var("SLEUTH_SCRATCH_ROOT")
                .unwrap_or_else(|_| "./var/sleuth/scratch".into());
            let scratch_dir = PathBuf::from(scratch_root).join(&case);
            let receipt = exec(&pool, &case, &tool, parsed, validation, case_dir, scratch_dir).await?;
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
    case_dir: PathBuf,
    scratch_dir: PathBuf,
) -> Result<Value> {
    // Allowlist gate.
    let spec = allowlist::get(pool, tool_name).await?
        .with_context(|| format!("tool not in allowlist: {tool_name}"))?;

    // JSON Schema gate (broker-side; pg-side mirror in Phase 2).
    schema::validate(&spec.args_schema, &args)
        .context("args failed schema validation (broker rejected before exec)")?;

    let tool_call_id = db::record_tool_call_start(pool, case, tool_name, &args, validation).await?;

    let seccomp = env::var("SLEUTH_SECCOMP_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            // default: project-relative
            std::env::current_dir().unwrap_or_default()
                .join("broker/seccomp/sleuth.json")
        });

    let result = podman::run(&spec, &args, &case_dir, &scratch_dir, &seccomp).await?;

    let blob_root = stream::default_root();
    let writer = stream::BlobWriter::new(&blob_root);
    let stdout_hash = writer.ingest(pool, &result.stdout, Some("application/octet-stream")).await?;
    let stderr_hash = writer.ingest(pool, &result.stderr, Some("text/plain")).await?;

    db::record_tool_call_finish(
        pool, tool_call_id,
        result.exit_code, result.duration_ms,
        Some(stdout_hash.as_slice()),
        Some(stderr_hash.as_slice()),
    ).await?;

    Ok(serde_json::json!({
        "tool_call_id": tool_call_id,
        "tool":         tool_name,
        "case":         case,
        "validation":   validation,
        "exit_code":    result.exit_code,
        "duration_ms":  result.duration_ms,
        "stdout_hash":  format!("blake3:{}", hex::encode(stdout_hash)),
        "stderr_hash":  format!("blake3:{}", hex::encode(stderr_hash)),
        "stdout_size":  result.stdout.len(),
        "stderr_size":  result.stderr.len(),
        "stdout_preview": String::from_utf8_lossy(&result.stdout[..result.stdout.len().min(4096)]),
        "stderr_tail":  String::from_utf8_lossy(
            &result.stderr[result.stderr.len().saturating_sub(4096)..]
        ),
        "stdout": String::from_utf8_lossy(&result.stdout[..result.stdout.len().min(4096)]),
        "stderr": String::from_utf8_lossy(
            &result.stderr[result.stderr.len().saturating_sub(4096)..]
        ),
    }))
}

fn init_tracing() {
    let level = env::var("RUST_LOG").unwrap_or_else(|_| "info".into());
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::new(level))
        .with_target(false).compact().init();
}
