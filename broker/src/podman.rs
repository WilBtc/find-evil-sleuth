//! Podman sandbox runner. Phase 1.5 lands here.
//!
//! Builds a `podman run` invocation from a ToolSpec + validated args, runs it
//! with rootless + seccomp + read-only + cap-drop ALL + no-net, streams stdout
//! and stderr through blake3 hashers into the evidence-store blob dir, returns
//! exit code + duration + content hashes.
//!
//! NOTE for vol3: do NOT pipe its stdout (exit code masking — see plan 02).
//! Use `--rm -e VOL_OUTDIR=/scratch/out` and read the file post-run.

#![allow(dead_code)]

use anyhow::Result;
use crate::allowlist::ToolSpec;
use serde_json::Value;

pub struct RunResult {
    pub exit_code:    i32,
    pub duration_ms:  i32,
    pub stdout_hash:  [u8; 32],
    pub stderr_hash:  [u8; 32],
    pub container_id: String,
}

pub async fn run(_spec: &ToolSpec, _args: &Value, _case_dir: &str) -> Result<RunResult> {
    todo!("Phase 1.5 — wire podman invocation per plans/02-broker-design.md")
}
