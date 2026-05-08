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
