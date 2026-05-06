//! Podman sandbox runner.
//!
//! Builds a `podman run` invocation from a ToolSpec + validated args, runs it
//! rootless with seccomp, read-only rootfs, dropped capabilities, no network.
//! Streams stdout/stderr through blake3 hashers into the blob store.
//!
//! NOTE for vol3 (validated 2026-05-06): vol3 exit code is masked when stdout
//! is consumed by a pipe. We capture stdout via tokio::process::Command into
//! a Vec<u8> directly (no shell pipe) — exit code is preserved.

use anyhow::{Context, Result};
use crate::allowlist::ToolSpec;
use serde_json::Value;
use std::path::Path;
use std::process::Stdio;
use std::time::Instant;
use tokio::process::Command;

pub struct RunResult {
    pub exit_code:    i32,
    pub duration_ms:  i32,
    pub stdout:       Vec<u8>,
    pub stderr:       Vec<u8>,
    pub container_id: String,
}

pub async fn run(
    spec: &ToolSpec,
    args: &Value,
    case_dir: &Path,
    seccomp_path: &Path,
) -> Result<RunResult> {
    let started = Instant::now();
    let mut cmd = Command::new("podman");

    let case_dir_str = case_dir.canonicalize()
        .with_context(|| format!("case_dir not accessible: {}", case_dir.display()))?
        .display()
        .to_string();

    cmd.arg("run")
       .arg("--rm")
       .arg("--read-only")
       .arg("--read-only-tmpfs")
       .arg("--tmpfs").arg("/tmp:rw,size=512m,mode=1777")
       .arg("--tmpfs").arg("/scratch:rw,size=2g")
       .arg("--security-opt").arg("no-new-privileges")
       .arg("--security-opt").arg(format!("seccomp={}", seccomp_path.display()))
       .arg("--cap-drop").arg("ALL")
       .arg("--user").arg("65534:65534")
       .arg(format!("--memory={}m", spec.memory_mb))
       .arg(format!("--memory-swap={}m", spec.memory_mb))
       .arg(format!("--pids-limit={}", spec.pids_limit))
       .arg("--cpus").arg("4")
       .arg("--mount").arg(format!("type=bind,src={case_dir_str},dst=/case,ro"))
       .arg(format!("--network={}", spec.network));

    cmd.arg(&spec.image);
    cmd.args(tool_argv(spec, args)?);

    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let timeout = std::time::Duration::from_secs(spec.timeout_s as u64);
    let child = cmd.spawn().context("podman run spawn")?;
    let output = match tokio::time::timeout(timeout, child.wait_with_output()).await {
        Ok(r) => r.context("podman child wait")?,
        Err(_) => anyhow::bail!("tool exceeded timeout of {}s", spec.timeout_s),
    };

    Ok(RunResult {
        exit_code:    output.status.code().unwrap_or(-1),
        duration_ms:  started.elapsed().as_millis() as i32,
        stdout:       output.stdout,
        stderr:       output.stderr,
        container_id: String::new(), // podman --rm; kept for future structured tracking
    })
}

/// Map a tool's validated JSON args into a CLI argv vector.
///
/// Per-tool argv builders. Each tool has a tiny known shape after schema
/// validation, so this is a small match — broker doesn't speculate.
fn tool_argv(spec: &ToolSpec, args: &Value) -> Result<Vec<String>> {
    match spec.tool.as_str() {
        // sleuthkit fls --- list dir entries from a forensic image
        "fls" => {
            let mut v = vec!["fls".into()];
            let img = args.get("image").and_then(|x| x.as_str())
                .context("fls.args.image missing")?;
            // The schema constrains image to ^/case/, so we can pass it as-is.
            if let Some(off) = args.get("offset").and_then(|x| x.as_i64()) {
                v.push("-o".into()); v.push(off.to_string());
            }
            if args.get("recursive").and_then(|x| x.as_bool()).unwrap_or(false) {
                v.push("-r".into());
            }
            v.push(img.to_string());
            Ok(v)
        }
        // mmls --- partition map
        "mmls" => Ok(vec![
            "mmls".into(),
            args.get("image").and_then(|x| x.as_str())
                .context("mmls.args.image missing")?.to_string(),
        ]),
        // tshark — pcap analysis
        "tshark" => {
            let mut v = vec!["tshark".into(), "-r".into(),
                args.get("pcap").and_then(|x| x.as_str())
                    .context("tshark.args.pcap missing")?.to_string()];
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            Ok(v)
        }
        // editcap — pcap recovery
        "editcap" => Ok(vec![
            "editcap".into(),
            args.get("input").and_then(|x| x.as_str())
                .context("editcap.args.input missing")?.to_string(),
            args.get("output").and_then(|x| x.as_str())
                .context("editcap.args.output missing")?.to_string(),
        ]),
        // vol3 — memory forensics. NEVER pipe vol3 stdout (see plan 02).
        "vol3" => {
            let mut v = vec!["vol".into(), "-q".into(),
                "-f".into(),
                args.get("memory_image").and_then(|x| x.as_str())
                    .context("vol3.args.memory_image missing")?.to_string()];
            v.push(args.get("plugin").and_then(|x| x.as_str())
                .context("vol3.args.plugin missing")?.to_string());
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            Ok(v)
        }
        // icat --- extract file content by inode
        "icat" => {
            let mut v = vec!["icat".into()];
            if let Some(off) = args.get("offset").and_then(|x| x.as_i64()) {
                v.push("-o".into()); v.push(off.to_string());
            }
            v.push(args.get("image").and_then(|x| x.as_str())
                .context("icat.args.image missing")?.to_string());
            v.push(args.get("inode").and_then(|x| x.as_i64())
                .context("icat.args.inode missing")?.to_string());
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            Ok(v)
        }
        // tsk_recover --- recover allocated/deleted files
        "tsk_recover" => {
            let mut v = vec!["tsk_recover".into()];
            if let Some(off) = args.get("offset").and_then(|x| x.as_i64()) {
                v.push("-o".into()); v.push(off.to_string());
            }
            v.push("-e".into());
            v.push(args.get("image").and_then(|x| x.as_str())
                .context("tsk_recover.args.image missing")?.to_string());
            v.push(args.get("output_dir").and_then(|x| x.as_str())
                .context("tsk_recover.args.output_dir missing")?.to_string());
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            Ok(v)
        }
        // bulk_extractor --- carve IOCs from disk images
        "bulk_extractor" => {
            let mut v = vec!["bulk_extractor".into()];
            v.push("-o".into());
            v.push(args.get("output_dir").and_then(|x| x.as_str())
                .context("bulk_extractor.args.output_dir missing")?.to_string());
            v.push(args.get("image").and_then(|x| x.as_str())
                .context("bulk_extractor.args.image missing")?.to_string());
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            Ok(v)
        }
        // yara --- scan with YARA rules
        "yara" => {
            let mut v = vec!["yara".into()];
            if args.get("recursive").and_then(|x| x.as_bool()).unwrap_or(false) {
                v.push("-r".into());
            }
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            v.push(args.get("rules").and_then(|x| x.as_str())
                .context("yara.args.rules missing")?.to_string());
            v.push(args.get("target").and_then(|x| x.as_str())
                .context("yara.args.target missing")?.to_string());
            Ok(v)
        }
        // log2timeline.py --- build plaso timeline
        // Usage: log2timeline.py [opts] --storage_file PATH SOURCE
        "log2timeline" => {
            let mut v = vec!["log2timeline.py".into()];
            v.push("--storage_file".into());
            v.push(args.get("output_file").and_then(|x| x.as_str())
                .context("log2timeline.args.output_file missing")?.to_string());
            if let Some(parsers) = args.get("parsers").and_then(|x| x.as_str()) {
                v.push("--parsers".into()); v.push(parsers.to_string());
            }
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            v.push(args.get("image").and_then(|x| x.as_str())
                .context("log2timeline.args.image missing")?.to_string());
            Ok(v)
        }
        // psort.py --- sort/filter a plaso storage file
        "psort" => {
            let mut v = vec!["psort.py".into()];
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            v.push("-o".into()); v.push("dynamic".into());
            v.push("-w".into());
            v.push(args.get("output_file").and_then(|x| x.as_str())
                .context("psort.args.output_file missing")?.to_string());
            let storage = args.get("storage_file").or_else(|| args.get("input"))
                .and_then(|x| x.as_str())
                .context("psort.args.storage_file missing")?;
            v.push(storage.to_string());
            Ok(v)
        }
        other => anyhow::bail!("no argv builder registered for tool: {other}"),
    }
}
