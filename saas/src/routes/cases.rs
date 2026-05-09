use axum::{
    extract::State,
    response::{Html, Json},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use crate::AppState;

#[derive(Debug, Serialize, FromRow)]
pub struct CaseRow {
    pub case_id:    String,
    pub name:       String,
    pub started_at: chrono::DateTime<chrono::Utc>,
    pub status:     String,
    pub total:      i64,
    pub confirmed:  i64,
    pub pending:    i64,
    pub refuted:    i64,
}

pub async fn cases_list(State(state): State<AppState>) -> Html<String> {
    let rows = sqlx::query_as::<_, CaseRow>(
        r#"
        SELECT
            c.case_id,
            c.name,
            c.started_at,
            c.status,
            COUNT(f.finding_id)                                         AS total,
            COUNT(f.finding_id) FILTER (WHERE f.validation_status = 'confirmed')  AS confirmed,
            COUNT(f.finding_id) FILTER (WHERE f.validation_status = 'pending')    AS pending,
            COUNT(f.finding_id) FILTER (WHERE f.validation_status = 'refuted')    AS refuted
        FROM cases c
        LEFT JOIN findings f ON f.case_id = c.case_id
        GROUP BY c.case_id, c.name, c.started_at, c.status
        ORDER BY c.started_at DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await;

    let cases = match rows {
        Ok(v) => v,
        Err(e) => {
            return Html(format!(
                "<pre>DB error: {e}</pre>"
            ));
        }
    };

    let mut ctx = tera::Context::new();
    ctx.insert("cases", &cases);

    let body = state
        .tera
        .render("cases_list.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

pub async fn cases_list_partial(State(state): State<AppState>) -> Html<String> {
    let rows = sqlx::query_as::<_, CaseRow>(
        r#"
        SELECT
            c.case_id,
            c.name,
            c.started_at,
            c.status,
            COUNT(f.finding_id)                                         AS total,
            COUNT(f.finding_id) FILTER (WHERE f.validation_status = 'confirmed')  AS confirmed,
            COUNT(f.finding_id) FILTER (WHERE f.validation_status = 'pending')    AS pending,
            COUNT(f.finding_id) FILTER (WHERE f.validation_status = 'refuted')    AS refuted
        FROM cases c
        LEFT JOIN findings f ON f.case_id = c.case_id
        GROUP BY c.case_id, c.name, c.started_at, c.status
        ORDER BY c.started_at DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await;

    let cases = match rows {
        Ok(v) => v,
        Err(e) => {
            return Html(format!("<pre>DB error: {e}</pre>"));
        }
    };

    let mut ctx = tera::Context::new();
    ctx.insert("cases", &cases);

    let body = state
        .tera
        .render("_partials/cases_table.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

// ── POST /cases/new — create case + optionally launch ADW ──────────

#[derive(Debug, Deserialize)]
pub struct NewCaseReq {
    /// Slug-style name. Becomes the case_id and the directory name.
    pub case_id: String,
    /// Free-form display name. Defaults to case_id when empty.
    pub name:    Option<String>,
    /// "empty"          — create dir + cases row, do nothing else.
    /// "investigate"    — create dir + spawn ./scripts/investigate.sh in background.
    /// "fetch_lonewolf" — pull SANS LoneWolf + investigate (legacy, kept for compat).
    /// "fetch_dataset"  — pull `dataset` via scripts/fetch-dataset.sh, then investigate.
    pub mode:    String,
    /// Required when mode == "fetch_dataset". One of:
    ///   lone-wolf | cridex | cfreds-hacking | nitroba | dfrws-2008-mem | m57-jean | honeynet-6
    pub dataset: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct NewCaseResp {
    pub case_id:     String,
    pub redirect_to: String,
    pub log_path:    Option<String>,
}

#[derive(Debug, Serialize)]
pub struct NewCaseErr {
    pub error: String,
}

/// Validate slug: 1..64 chars of [a-zA-Z0-9_-], no path traversal.
fn valid_slug(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

pub async fn new_case(
    State(state): State<AppState>,
    Json(req): Json<NewCaseReq>,
) -> Result<Json<NewCaseResp>, (StatusCode, Json<NewCaseErr>)> {
    if !valid_slug(&req.case_id) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(NewCaseErr { error: "case_id must be 1–64 chars of [A-Za-z0-9_-]".into() }),
        ));
    }
    let mode = req.mode.as_str();
    if !matches!(mode, "empty" | "investigate" | "fetch_lonewolf") {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(NewCaseErr { error: format!("unknown mode: {}", mode) }),
        ));
    }

    let display_name = req.name.unwrap_or_else(|| req.case_id.clone());

    // Workspace root = parent of saas/ (CARGO_MANIFEST_DIR is saas/)
    let repo_root: PathBuf = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));

    let case_dir = repo_root.join("cases").join(&req.case_id);
    if let Err(e) = std::fs::create_dir_all(&case_dir) {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(NewCaseErr { error: format!("mkdir {}: {}", case_dir.display(), e) }),
        ));
    }

    // INSERT cases row with status='triage' — the lowest state-machine
    // step. investigate.py's state_init can resume from there cleanly.
    // (status='pending' or 'running' would be rejected as "unknown state".)
    let inserted = sqlx::query(
        r#"INSERT INTO cases (case_id, name, status)
           VALUES ($1, $2, 'triage')
           ON CONFLICT (case_id) DO NOTHING
           RETURNING case_id"#,
    )
    .bind(&req.case_id)
    .bind(&display_name)
    .fetch_optional(&state.pool)
    .await;

    if let Err(e) = inserted {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(NewCaseErr { error: format!("db insert: {}", e) }),
        ));
    }

    // Spawn ADW driver as detached background process. Logs to logs/cases/<id>.log
    let log_dir = repo_root.join("logs").join("cases");
    let _ = std::fs::create_dir_all(&log_dir);
    let log_path = log_dir.join(format!("{}.log", &req.case_id));
    let log_path_str = log_path.display().to_string();

    let mut log_path_resp = None;

    match mode {
        "empty" => {
            // Just leave the case as 'pending'. User drops evidence, runs
            // investigate.sh from terminal when ready.
        }
        "investigate" => {
            log_path_resp = Some(log_path_str.clone());
            spawn_adw(&repo_root, &case_dir, &log_path)
                .map_err(|e| (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(NewCaseErr { error: format!("spawn investigate.sh: {}", e) }),
                ))?;
            // intentionally NOT setting status='running' here — investigate.py
            // owns the state machine; flipping it pre-spawn confuses the
            // resume path.
        }
        "fetch_lonewolf" => {
            log_path_resp = Some(log_path_str.clone());
            spawn_fetch_then_investigate(&repo_root, &case_dir, &log_path)
                .map_err(|e| (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(NewCaseErr { error: format!("spawn fetch+investigate: {}", e) }),
                ))?;
            // intentionally NOT setting status='running' here — investigate.py
            // owns the state machine; flipping it pre-spawn confuses the
            // resume path.
        }
        _ => unreachable!(),
    }

    Ok(Json(NewCaseResp {
        case_id:     req.case_id.clone(),
        redirect_to: format!("/case/{}", &req.case_id),
        log_path:    log_path_resp,
    }))
}

fn spawn_adw(repo_root: &PathBuf, case_dir: &PathBuf, log_path: &PathBuf) -> std::io::Result<()> {
    let log = std::fs::OpenOptions::new()
        .create(true).append(true).open(log_path)?;
    let log_err = log.try_clone()?;

    Command::new("setsid")
        .arg("./scripts/investigate.sh")
        .arg(case_dir)
        .current_dir(repo_root)
        .stdin(Stdio::null())
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(log_err))
        .spawn()
        .map(|_| ())
}

fn spawn_fetch_then_investigate(
    repo_root: &PathBuf,
    case_dir: &PathBuf,
    log_path: &PathBuf,
) -> std::io::Result<()> {
    let log = std::fs::OpenOptions::new()
        .create(true).append(true).open(log_path)?;
    let log_err = log.try_clone()?;

    // Chain: fetch then investigate, in a detached shell.
    let case_dir_str = case_dir.display().to_string();
    let cmd = format!(
        "./scripts/fetch-evidence.sh lone-wolf && \
         cp -r evidence-samples/lone-wolf/* {dst}/ && \
         ./scripts/investigate.sh {dst}",
        dst = case_dir_str,
    );

    Command::new("setsid")
        .arg("bash").arg("-c").arg(cmd)
        .current_dir(repo_root)
        .stdin(Stdio::null())
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(log_err))
        .spawn()
        .map(|_| ())
}

// ── GET /case/:id/log — tail the spawned-job log for live updates ──

use axum::extract::Path;

pub async fn case_log_tail(
    State(_state): State<AppState>,
    Path(case_id): Path<String>,
) -> (StatusCode, String) {
    if !valid_slug(&case_id) {
        return (StatusCode::BAD_REQUEST, "invalid case_id".into());
    }
    let repo_root: PathBuf = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent().map(|p| p.to_path_buf()).unwrap_or_else(|| PathBuf::from("."));
    let log_path = repo_root.join("logs").join("cases").join(format!("{}.log", case_id));
    match std::fs::read_to_string(&log_path) {
        Ok(s) => {
            // Return last 8 KB.
            let n = s.len();
            let start = n.saturating_sub(8 * 1024);
            (StatusCode::OK, s[start..].to_string())
        }
        Err(_) => (StatusCode::OK, String::from("(no log yet)")),
    }
}
