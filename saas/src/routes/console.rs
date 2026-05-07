use axum::{
    extract::State,
    response::{Html, Json},
};
use serde::{Deserialize, Serialize};
use sqlx::{Column, Row, TypeInfo};
use crate::AppState;

#[derive(Debug, Deserialize)]
pub struct ConsoleQuery {
    pub sql: String,
}

#[derive(Debug, Serialize)]
pub struct ConsoleResult {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<serde_json::Value>>,
    pub row_count: usize,
    pub error: Option<String>,
    pub duration_ms: u64,
}

pub async fn console_page(State(state): State<AppState>) -> Html<String> {
    let ctx = tera::Context::new();
    let body = state
        .tera
        .render("console.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

pub async fn console_query(
    State(_state): State<AppState>,
    axum::Json(payload): axum::Json<ConsoleQuery>,
) -> Json<ConsoleResult> {
    let sql = payload.sql.trim().to_string();

    if sql.is_empty() {
        return Json(ConsoleResult {
            columns: vec![],
            rows: vec![],
            row_count: 0,
            error: Some("Empty query".into()),
            duration_ms: 0,
        });
    }

    let ro_url = {
        let host = std::env::var("PG_HOST").unwrap_or_else(|_| "127.0.0.1".into());
        let port = std::env::var("PG_PORT").unwrap_or_else(|_| "5532".into());
        let db   = std::env::var("PG_DB").unwrap_or_else(|_| "sleuth".into());
        let user = std::env::var("PG_RO_USER").unwrap_or_else(|_| "sleuth_ro_user".into());
        let pw   = std::env::var("PG_RO_PASSWORD").unwrap_or_else(|_| "changeme-ro-dev-only".into());
        format!("postgres://{user}:{pw}@{host}:{port}/{db}")
    };

    let ro_pool = match sqlx::postgres::PgPoolOptions::new()
        .max_connections(1)
        .connect(&ro_url)
        .await
    {
        Ok(p) => p,
        Err(e) => {
            return Json(ConsoleResult {
                columns: vec![],
                rows: vec![],
                row_count: 0,
                error: Some(format!("Cannot connect as sleuth_ro: {e}")),
                duration_ms: 0,
            });
        }
    };

    let start = std::time::Instant::now();
    let result = sqlx::query(&sql).fetch_all(&ro_pool).await;
    let duration_ms = start.elapsed().as_millis() as u64;
    ro_pool.close().await;

    match result {
        Ok(rows) => {
            if rows.is_empty() {
                return Json(ConsoleResult {
                    columns: vec![],
                    rows: vec![],
                    row_count: 0,
                    error: None,
                    duration_ms,
                });
            }

            let columns: Vec<String> = rows[0]
                .columns()
                .iter()
                .map(|c| c.name().to_string())
                .collect();

            let mut result_rows: Vec<Vec<serde_json::Value>> = Vec::new();
            for row in &rows {
                let mut cells: Vec<serde_json::Value> = Vec::new();
                for (i, col) in row.columns().iter().enumerate() {
                    let type_name = col.type_info().name();
                    let cell = pg_col_to_json(row, i, type_name);
                    cells.push(cell);
                }
                result_rows.push(cells);
            }

            let row_count = result_rows.len();
            Json(ConsoleResult {
                columns,
                rows: result_rows,
                row_count,
                error: None,
                duration_ms,
            })
        }
        Err(e) => Json(ConsoleResult {
            columns: vec![],
            rows: vec![],
            row_count: 0,
            error: Some(e.to_string()),
            duration_ms,
        }),
    }
}

fn pg_col_to_json(row: &sqlx::postgres::PgRow, i: usize, type_name: &str) -> serde_json::Value {
    match type_name {
        "INT2" => row.try_get::<i16, _>(i)
            .map(|v| serde_json::Value::Number(v.into()))
            .unwrap_or(serde_json::Value::Null),
        "INT4" => row.try_get::<i32, _>(i)
            .map(|v| serde_json::Value::Number(v.into()))
            .unwrap_or(serde_json::Value::Null),
        "INT8" => row.try_get::<i64, _>(i)
            .map(|v| serde_json::Value::Number(v.into()))
            .unwrap_or(serde_json::Value::Null),
        "FLOAT4" => row.try_get::<f32, _>(i)
            .map(|v| serde_json::Number::from_f64(v as f64)
                .map(serde_json::Value::Number)
                .unwrap_or(serde_json::Value::Null))
            .unwrap_or(serde_json::Value::Null),
        "FLOAT8" => row.try_get::<f64, _>(i)
            .map(|v| serde_json::Number::from_f64(v)
                .map(serde_json::Value::Number)
                .unwrap_or(serde_json::Value::Null))
            .unwrap_or(serde_json::Value::Null),
        "BOOL" => row.try_get::<bool, _>(i)
            .map(serde_json::Value::Bool)
            .unwrap_or(serde_json::Value::Null),
        "JSON" | "JSONB" => row.try_get::<serde_json::Value, _>(i)
            .unwrap_or(serde_json::Value::Null),
        _ => {
            if let Ok(v) = row.try_get::<Option<String>, _>(i) {
                match v {
                    Some(s) => serde_json::Value::String(s),
                    None => serde_json::Value::Null,
                }
            } else {
                serde_json::Value::String("<unrenderable>".into())
            }
        }
    }
}
