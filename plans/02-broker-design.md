# 02 · sleuth-broker (Rust)

> The broker is the architectural guardrail. The agent never executes a forensics tool directly — it always goes through `./bin/sb`. The Bash hook ensures it.

## Single binary, one verb

```
sb exec --case <case_id> --tool <name> --args '<json>' [--validation]
sb list-tools
sb describe <tool>
```

Output (stdout, JSON, one object):
```json
{
  "tool_call_id": "uuid",
  "exit_code": 0,
  "duration_ms": 8732,
  "stdout_hash": "blake3:…",
  "stderr_hash": "blake3:…",
  "artifact_hash": "blake3:…",
  "container_id": "podman:…",
  "stdout_preview": "first 4KB",
  "stderr_tail": "last 4KB"
}
```

Exit codes: 0 if podman ran (regardless of tool's own exit), 2 if validation rejected the args, 3 if allowlist rejected the tool, 4 if timeout, 5 if internal broker error.

## Tool spec format (`broker/tools/<name>.toml`)

```toml
tool = "vol3"
image = "find-evil-sleuth/volatility3:3.x"
entrypoint = ["vol", "-q"]
timeout_s = 1200
memory_mb = 8192
pids_limit = 512
network = "none"

# JSON Schema draft 2020-12 — broker validates via pg_jsonschema before running
args_schema = '''
{
  "type": "object",
  "required": ["plugin","memory_image"],
  "properties": {
    "plugin":       {"enum":["windows.info","windows.pslist","windows.pstree","windows.cmdline","windows.dlllist","windows.handles","windows.malfind","windows.netscan","windows.svcscan","windows.registry.printkey","banners"]},
    "memory_image": {"type":"string","pattern":"^/case/memory/[A-Za-z0-9._-]+$"},
    "extra_args":   {"type":"array","items":{"type":"string"},"maxItems":8}
  },
  "additionalProperties": false
}
'''
```

The path-pattern constraint is the *second* sandbox: even if podman lets the tool see `/etc/`, the broker won't accept a path outside the case mount.

## Podman invocation (built dynamically)

```
podman run \
  --rm \
  --read-only \
  --read-only-tmpfs \
  --tmpfs /tmp:rw,size=512m,mode=1777 \
  --tmpfs /scratch:rw,size=2g \
  --network=none \
  --security-opt no-new-privileges \
  --security-opt seccomp=/etc/sleuth/seccomp/sleuth.json \
  --cap-drop ALL \
  --user 65534:65534 \
  --memory ${memory_mb}m --memory-swap ${memory_mb}m \
  --pids-limit ${pids_limit} \
  --cpus 4 \
  --mount type=bind,src=${case_dir},dst=/case,ro,relabel=shared \
  --label sleuth.tool_call_id=${uuid} \
  ${image} ${entrypoint[@]} ${tool_args[@]}
```

`--cap-drop ALL` + `--user 65534:65534` + `--read-only` + `no-new-privileges` is the architectural belt-and-braces. seccomp is the suspenders.

## Seccomp profile

Start from `runc` default profile, additionally deny:
- `ptrace` (no debugging escape)
- `mount`, `umount2`, `pivot_root`, `chroot`
- `unshare`, `setns` with non-zero flags
- `bpf`, `perf_event_open`, `kexec_load`
- `personality` non-default
- All `*module*` syscalls

Allow listed forensics-needed syscalls verified by running each tool once on baseline evidence and capturing strace.

## Streaming stdout/stderr to evidence-store

Broker pipes podman's `stdout`/`stderr` through a writer that:
1. Hashes (blake3 streaming)
2. Writes to `/var/sleuth/blobs/<aa>/<bb>/<full-hex>` (sharded by first 4 hex chars)
3. After EOF: `INSERT INTO artifacts ...` if hash unseen
4. Captures first 4KB and last 4KB for response preview

stdout and stderr stored separately. Broker never returns the full payload to the agent — only the hash + previews + a cursor to fetch ranges via `es get-bytes <hash> --offset --len`.

## Resource caps

Per-tool from spec; case-level cap enforced by broker: max `concurrent_tool_calls=4`, `max_runtime_per_case=2h`. Exceeding caps returns exit 4 with a structured error the agent can self-correct around.

## Validation mode

`--validation` flag sets `tool_calls.is_validation = true` and disables short-circuit dedup. Used by `findings-validator` agent so re-runs always happen even if hash matches.

## Cargo crate map

```
broker/
├── Cargo.toml             # tokio, sqlx, blake3, serde, jsonschema, clap, podman-api?
└── src/
    ├── main.rs            # clap commands
    ├── allowlist.rs       # load tool_specs from DB cache, refresh per call
    ├── schema.rs          # jsonschema validate args
    ├── podman.rs          # build & run subprocess; not the SDK (avoid daemon coupling)
    ├── stream.rs          # blake3 streaming + blob writer
    ├── seccomp.rs         # render profile path, sanity check exists
    └── db.rs              # sqlx pool, insert tool_calls / artifacts
```

Build: `cargo build --release` → `./bin/sb`.
