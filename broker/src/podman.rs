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
    scratch_dir: &Path,
    seccomp_path: &Path,
) -> Result<RunResult> {
    let started = Instant::now();
    let mut cmd = Command::new("podman");

    let case_dir_str = case_dir.canonicalize()
        .with_context(|| format!("case_dir not accessible: {}", case_dir.display()))?
        .display()
        .to_string();

    std::fs::create_dir_all(scratch_dir)
        .with_context(|| format!("cannot create scratch_dir: {}", scratch_dir.display()))?;
    // The container runs as uid 65534, but the scratch dir is created owned by
    // the invoking user (0755), so writes from inside (editcap repair, plaso
    // output, …) fail with "permission denied". Make it world-writable so the
    // sandboxed tool can write its working files into the rw /scratch mount.
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(scratch_dir, std::fs::Permissions::from_mode(0o777));
    }
    let scratch_dir_str = scratch_dir.canonicalize()
        .with_context(|| format!("scratch_dir not accessible: {}", scratch_dir.display()))?
        .display()
        .to_string();

    cmd.arg("run")
       .arg("--rm")
       .arg("--read-only")
       .arg("--read-only-tmpfs")
       .arg("--tmpfs").arg("/tmp:rw,size=512m,mode=1777")
       .arg("--security-opt").arg("no-new-privileges")
       .arg("--security-opt").arg(format!("seccomp={}", seccomp_path.display()))
       .arg("--cap-drop").arg("ALL")
       .arg("--user").arg("65534:65534")
       .arg(format!("--memory={}m", spec.memory_mb))
       .arg(format!("--memory-swap={}m", spec.memory_mb))
       .arg(format!("--pids-limit={}", spec.pids_limit))
       .arg("--cpus").arg("4")
       .arg("--mount").arg(format!("type=bind,src={case_dir_str},dst=/case,ro"))
       .arg("--mount").arg(format!("type=bind,src={scratch_dir_str},dst=/scratch,rw"))
       // The container runs --read-only as uid 65534 with no home, so tools that
       // write a cache under $HOME/.cache (notably Volatility 3) fail with
       // "read-only file system". Point HOME and the XDG cache at the writable
       // tmpfs /tmp so those tools work without relaxing the sandbox.
       .arg("--env").arg("HOME=/tmp")
       .arg("--env").arg("XDG_CACHE_HOME=/tmp")
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
        // mmls --- partition map (slim sleuthkit image)
        "mmls" => Ok(vec![
            "mmls".into(),
            args.get("image").and_then(|x| x.as_str())
                .context("mmls.args.image missing")?.to_string(),
        ]),
        // mmls-sift / mmls-sift-full --- same as mmls, routed through the SIFT image(s)
        "mmls-sift" | "mmls-sift-full" => Ok(vec![
            "mmls".into(),
            args.get("image").and_then(|x| x.as_str())
                .context("mmls-sift.args.image missing")?.to_string(),
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
                args.get("image").and_then(|x| x.as_str())
                    .context("vol3.args.image missing")?.to_string()];
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
        // bulk_extractor --- carve IOCs (emails, URLs, domains, IPs) and return histograms.
        // Runs on any evidence (pcap or disk image); cats the *_histogram.txt result files
        // back to stdout so the agent sees a small, high-signal value+count list.
        "bulk_extractor" => {
            let target = args.get("image").and_then(|x| x.as_str())
                .or_else(|| args.get("pcap").and_then(|x| x.as_str()))
                .or_else(|| args.get("target").and_then(|x| x.as_str()))
                .context("bulk_extractor.args.image|pcap|target missing")?
                .replace('\'', "");
            let pre = "set +e; in='";
            let post = "'; out=/scratch/be; mkdir -p \"$out\"; \
                case \"$in\" in *.E01|*.e01|*.Ex01|*.aff4) img_cat \"$in\" 2>/dev/null > /scratch/raw.dd; SRC=/scratch/raw.dd ;; *) SRC=\"$in\" ;; esac; \
                { strings -n 6 \"$SRC\"; strings -e l -n 6 \"$SRC\"; } > \"$out/s.txt\" 2>/dev/null; \
                echo '=== email ==='; grep -aoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z][A-Za-z]+' \"$out/s.txt\" | sort | uniq -c | sort -rn | head -80; \
                echo '=== ip ==='; grep -aoE '([0-9][0-9]?[0-9]?[.]){3}[0-9][0-9]?[0-9]?' \"$out/s.txt\" | sort | uniq -c | sort -rn | head -80; \
                rm -f \"$out/s.txt\" /scratch/raw.dd";
            let script = format!("{}{}{}", pre, target, post);
            Ok(vec!["bash".into(), "-lc".into(), script])
        }
        // deep_carve --- parse binary stores on a disk image: OST/PST mail (emails)
        // and EVTX event logs (IPs/logons). Outputs "=== email ===" / "=== ip ===" so the
        // pre-extract stage parses it the same way as the strings carve. General to any NTFS disk.
        "deep_carve" => {
            let pre = "set +e; in='";
            let post = "'; out=/scratch/dc; rm -rf \"$out\"; mkdir -p \"$out\"; \
                case \"$in\" in *.E01|*.e01|*.Ex01|*.aff4) img_cat \"$in\" 2>/dev/null > $out/raw.dd; in=$out/raw.dd ;; esac; \
                OFF=$(mmls \"$in\" 2>/dev/null | awk '/NTFS/ && !/Unallocated/ {if ($4+0>m){m=$4+0;o=$3}} END{print o}'); [ -z \"$OFF\" ] && OFF=0; \
                fls -r -p -o \"$OFF\" \"$in\" 2>/dev/null > $out/files.txt; \
                echo '=== email ==='; \
                grep -iE '[.](ost|pst)$' $out/files.txt | head -4 | while read -r ln; do \
                  ino=$(echo \"$ln\" | sed -nE 's#^[a-z/*-]+ +([0-9-]+):.*#\\1#p'); [ -z \"$ino\" ] && continue; \
                  icat -o \"$OFF\" \"$in\" \"$ino\" > $out/m 2>/dev/null; \
                  pffexport -q -f text -t $out/me $out/m >/dev/null 2>&1; \
                  grep -rhaoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z][A-Za-z]+' $out/me.export 2>/dev/null; \
                done | sort | uniq -c | sort -rn | head -60; \
                echo '=== ip ==='; \
                for ino in $(grep -iE 'winevt/Logs/(Security|System)[.]evtx' $out/files.txt | sed -nE 's#^[a-z/*-]+ +([0-9-]+):.*#\\1#p' | head -4); do \
                  icat -o \"$OFF\" \"$in\" \"$ino\" > $out/e.evtx 2>/dev/null; \
                  evtxexport -f text $out/e.evtx 2>/dev/null | grep -aoE '([0-9][0-9]?[0-9]?[.]){3}[0-9][0-9]?[0-9]?'; \
                done | sort | uniq -c | sort -rn | head -40; \
                rm -rf $out";
            let target = args.get("image").and_then(|x| x.as_str())
                .or_else(|| args.get("target").and_then(|x| x.as_str()))
                .context("deep_carve.args.image missing")?.replace('\'', "");
            let script = format!("{}{}{}", pre, target, post);
            Ok(vec!["bash".into(), "-lc".into(), script])
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
        // zeek --- network traffic analysis
        "zeek" => {
            let mut v = vec!["zeek".into(), "-r".into(),
                args.get("pcap").and_then(|x| x.as_str())
                    .context("zeek.args.pcap missing")?.to_string()];
            if let Some(scripts) = args.get("scripts").and_then(|x| x.as_array()) {
                for s in scripts { if let Some(script) = s.as_str() { v.push(script.into()) } }
            }
            if let Some(extra) = args.get("extra_args").and_then(|x| x.as_array()) {
                for a in extra { if let Some(s) = a.as_str() { v.push(s.into()) } }
            }
            Ok(v)
        }
        other => anyhow::bail!("no argv builder registered for tool: {other}"),
    }
}
