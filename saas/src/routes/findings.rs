use axum::{
    extract::{Path, Query, State},
    response::Html,
};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use crate::AppState;

#[derive(Debug, Serialize, FromRow)]
pub struct FindingRow {
    pub finding_id:        String,
    pub case_id:           String,
    pub specialist:        String,
    pub claim:             String,
    pub confidence:        String,
    pub validation_status: String,
    pub mitre_technique:   Option<String>,
    pub created_at:        chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Serialize, FromRow)]
pub struct FindingDetail {
    pub finding_id:        String,
    pub case_id:           String,
    pub specialist:        String,
    pub claim:             String,
    pub confidence:        String,
    pub validation_status: String,
    pub mitre_technique:   Option<String>,
    pub created_at:        chrono::DateTime<chrono::Utc>,
    pub last_validated_at: Option<chrono::DateTime<chrono::Utc>>,
    pub superseded_by:     Option<String>,
    pub tool_call_id:      String,
    pub byte_offset:       Option<i64>,
}

#[derive(Debug, Serialize, FromRow)]
pub struct ToolCallDetail {
    pub tool_call_id: String,
    pub tool:         String,
    pub args:         serde_json::Value,
    pub exit_code:    Option<i32>,
    pub duration_ms:  Option<i32>,
    pub started_at:   chrono::DateTime<chrono::Utc>,
    pub finished_at:  Option<chrono::DateTime<chrono::Utc>>,
    pub is_validation: bool,
}

#[derive(Debug, Serialize, FromRow)]
pub struct ValidationRunRow {
    pub run_id:     String,
    pub started_at: chrono::DateTime<chrono::Utc>,
    pub result:     Option<String>,
    pub diff:       Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
pub struct FindingsFilter {
    pub validation_status: Option<String>,
    pub specialist:        Option<String>,
    pub sort:              Option<String>,
}

pub async fn findings_list(
    State(state): State<AppState>,
    Path(case_id): Path<String>,
    Query(filter): Query<FindingsFilter>,
) -> Html<String> {
    let case_row = sqlx::query_as::<_, (String, String, String)>(
        "SELECT case_id, name, status FROM cases WHERE case_id = $1",
    )
    .bind(&case_id)
    .fetch_optional(&state.pool)
    .await;

    let (case_id_val, case_name, case_status) = match case_row {
        Ok(Some(row)) => row,
        Ok(None) => {
            return Html(format!("<pre>Case '{}' not found</pre>", html_escape(&case_id)));
        }
        Err(e) => return Html(format!("<pre>DB error: {e}</pre>")),
    };

    let vs_filter = filter.validation_status.as_deref().unwrap_or("");
    let sp_filter = filter.specialist.as_deref().unwrap_or("");

    let order_col = match filter.sort.as_deref() {
        Some("specialist") => "specialist ASC, finding_id ASC",
        Some("status")     => "validation_status ASC, finding_id ASC",
        Some("confidence") => "confidence ASC, finding_id ASC",
        Some("mitre")      => "mitre_technique ASC NULLS LAST, finding_id ASC",
        _                  => "finding_id ASC",
    };

    let findings: Vec<FindingRow> = if vs_filter.is_empty() && sp_filter.is_empty() {
        sqlx::query_as::<_, FindingRow>(&format!(
            r#"SELECT finding_id, case_id, specialist, claim, confidence,
                      validation_status, mitre_technique, created_at
               FROM findings
               WHERE case_id = $1
               ORDER BY {order_col}"#
        ))
        .bind(&case_id_val)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default()
    } else if vs_filter.is_empty() {
        sqlx::query_as::<_, FindingRow>(&format!(
            r#"SELECT finding_id, case_id, specialist, claim, confidence,
                      validation_status, mitre_technique, created_at
               FROM findings
               WHERE case_id = $1 AND specialist = $2
               ORDER BY {order_col}"#
        ))
        .bind(&case_id_val)
        .bind(sp_filter)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default()
    } else if sp_filter.is_empty() {
        sqlx::query_as::<_, FindingRow>(&format!(
            r#"SELECT finding_id, case_id, specialist, claim, confidence,
                      validation_status, mitre_technique, created_at
               FROM findings
               WHERE case_id = $1 AND validation_status = $2
               ORDER BY {order_col}"#
        ))
        .bind(&case_id_val)
        .bind(vs_filter)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default()
    } else {
        sqlx::query_as::<_, FindingRow>(&format!(
            r#"SELECT finding_id, case_id, specialist, claim, confidence,
                      validation_status, mitre_technique, created_at
               FROM findings
               WHERE case_id = $1 AND validation_status = $2 AND specialist = $3
               ORDER BY {order_col}"#
        ))
        .bind(&case_id_val)
        .bind(vs_filter)
        .bind(sp_filter)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default()
    };

    let distinct_specialists: Vec<(String,)> = sqlx::query_as(
        "SELECT DISTINCT specialist FROM findings WHERE case_id = $1 ORDER BY specialist",
    )
    .bind(&case_id_val)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let specialists: Vec<String> = distinct_specialists.into_iter().map(|(s,)| s).collect();

    let mut ctx = tera::Context::new();
    ctx.insert("case_id",   &case_id_val);
    ctx.insert("case_name", &case_name);
    ctx.insert("case_status", &case_status);
    ctx.insert("findings",  &findings);
    ctx.insert("total",     &findings.len());
    ctx.insert("filter_status",     &vs_filter);
    ctx.insert("filter_specialist", &sp_filter);
    ctx.insert("filter_sort",       filter.sort.as_deref().unwrap_or("id"));
    ctx.insert("specialists",       &specialists);

    let body = state
        .tera
        .render("findings_list.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

pub async fn finding_detail(
    State(state): State<AppState>,
    Path(finding_id): Path<String>,
) -> Html<String> {
    let finding = sqlx::query_as::<_, FindingDetail>(
        r#"SELECT finding_id, case_id, specialist, claim, confidence,
                  validation_status, mitre_technique, created_at,
                  last_validated_at, superseded_by,
                  tool_call_id::text, byte_offset
           FROM findings WHERE finding_id = $1"#,
    )
    .bind(&finding_id)
    .fetch_optional(&state.pool)
    .await;

    let finding = match finding {
        Ok(Some(f)) => f,
        Ok(None) => {
            return Html(format!("<pre>Finding '{}' not found</pre>", html_escape(&finding_id)));
        }
        Err(e) => return Html(format!("<pre>DB error: {e}</pre>")),
    };

    let tool_call = sqlx::query_as::<_, ToolCallDetail>(
        r#"SELECT tool_call_id::text, tool, args, exit_code, duration_ms,
                  started_at, finished_at, is_validation
           FROM tool_calls WHERE tool_call_id = $1::uuid"#,
    )
    .bind(&finding.tool_call_id)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    let validation_runs = sqlx::query_as::<_, ValidationRunRow>(
        r#"SELECT run_id::text, started_at, result, diff
           FROM validation_runs WHERE finding_id = $1
           ORDER BY started_at DESC"#,
    )
    .bind(&finding_id)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let args_json = tool_call.as_ref().map(|tc| {
        serde_json::to_string_pretty(&tc.args).unwrap_or_default()
    });

    let cite_json = build_cite_json(&finding, tool_call.as_ref(), &validation_runs);
    let cite_json_str = serde_json::to_string_pretty(&cite_json).unwrap_or_default();

    let mut ctx = tera::Context::new();
    ctx.insert("finding",         &finding);
    ctx.insert("tool_call",       &tool_call);
    ctx.insert("validation_runs", &validation_runs);
    ctx.insert("args_json",       &args_json);
    ctx.insert("cite_json",       &cite_json_str);

    let body = state
        .tera
        .render("findings_detail.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

/// HTMX side-drawer fragment for a finding. Same data as `finding_detail`
/// but a compact template that renders into `#drawer-host`.
pub async fn finding_drawer(
    State(state): State<AppState>,
    Path(finding_id): Path<String>,
) -> Html<String> {
    let finding = sqlx::query_as::<_, FindingDetail>(
        r#"SELECT finding_id, case_id, specialist, claim, confidence,
                  validation_status, mitre_technique, created_at,
                  last_validated_at, superseded_by,
                  tool_call_id::text, byte_offset
           FROM findings WHERE finding_id = $1"#,
    )
    .bind(&finding_id)
    .fetch_optional(&state.pool)
    .await;

    let finding = match finding {
        Ok(Some(f)) => f,
        Ok(None) => {
            return Html(format!(
                "<div class=\"drawer-backdrop\"></div><aside class=\"drawer-panel p-8\">Finding {} not found.</aside>",
                html_escape(&finding_id)
            ));
        }
        Err(e) => return Html(format!("<pre>DB error: {e}</pre>")),
    };

    let tool_call = sqlx::query_as::<_, ToolCallDetail>(
        r#"SELECT tool_call_id::text, tool, args, exit_code, duration_ms,
                  started_at, finished_at, is_validation
           FROM tool_calls WHERE tool_call_id = $1::uuid"#,
    )
    .bind(&finding.tool_call_id)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    let validation_runs = sqlx::query_as::<_, ValidationRunRow>(
        r#"SELECT run_id::text, started_at, result, diff
           FROM validation_runs WHERE finding_id = $1
           ORDER BY started_at DESC"#,
    )
    .bind(&finding_id)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let args_json = tool_call.as_ref().map(|tc| {
        serde_json::to_string_pretty(&tc.args).unwrap_or_default()
    });

    let cite_json = build_cite_json(&finding, tool_call.as_ref(), &validation_runs);
    let cite_json_str = serde_json::to_string_pretty(&cite_json).unwrap_or_default();

    let mut ctx = tera::Context::new();
    ctx.insert("finding",         &finding);
    ctx.insert("tool_call",       &tool_call);
    ctx.insert("validation_runs", &validation_runs);
    ctx.insert("args_json",       &args_json);
    ctx.insert("cite_json",       &cite_json_str);

    let body = state
        .tera
        .render("findings_drawer.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

fn build_cite_json(
    f: &FindingDetail,
    tc: Option<&ToolCallDetail>,
    runs: &[ValidationRunRow],
) -> serde_json::Value {
    let tc_val = tc.map(|t| {
        serde_json::json!({
            "tool_call_id": t.tool_call_id,
            "tool": t.tool,
            "args": t.args,
            "exit_code": t.exit_code,
            "duration_ms": t.duration_ms,
            "started_at": t.started_at.to_rfc3339(),
            "finished_at": t.finished_at.map(|dt| dt.to_rfc3339()),
            "is_validation": t.is_validation,
        })
    });

    let runs_val: Vec<serde_json::Value> = runs.iter().map(|r| {
        serde_json::json!({
            "run_id": r.run_id,
            "started_at": r.started_at.to_rfc3339(),
            "result": r.result,
            "diff": r.diff,
        })
    }).collect();

    serde_json::json!({
        "finding_id": f.finding_id,
        "case_id": f.case_id,
        "specialist": f.specialist,
        "claim": f.claim,
        "confidence": f.confidence,
        "validation_status": f.validation_status,
        "mitre_technique": f.mitre_technique,
        "created_at": f.created_at.to_rfc3339(),
        "last_validated_at": f.last_validated_at.map(|dt| dt.to_rfc3339()),
        "byte_offset": f.byte_offset,
        "tool_call": tc_val,
        "validation_history": runs_val,
    })
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
