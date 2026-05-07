use axum::{
    extract::{Path, State},
    response::{Html, Json},
};
use serde::Serialize;
use crate::AppState;

#[derive(Debug, Serialize)]
pub struct MerkleRootRow {
    pub root_id:      i64,
    pub case_id:      Option<String>,
    pub rolled_up_at: chrono::DateTime<chrono::Utc>,
    pub root_hash:    String,
    pub prev_root:    Option<String>,
    pub leaf_count:   i32,
}

#[derive(Debug, Serialize)]
pub struct VerifyResult {
    pub root_id:      i64,
    pub stored_hash:  String,
    pub derived_hash: String,
    pub leaf_count:   i32,
    pub ok:           bool,
}

pub async fn audit_page(
    State(state): State<AppState>,
    Path(case_id): Path<String>,
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

    let roots: Vec<MerkleRootRow> = sqlx::query_as::<_, (i64, Option<String>, chrono::DateTime<chrono::Utc>, String, Option<String>, i32)>(
        r#"SELECT root_id,
                  case_id,
                  rolled_up_at,
                  encode(root_hash, 'hex'),
                  encode(prev_root, 'hex'),
                  leaf_count
           FROM merkle_roots
           WHERE case_id = $1
           ORDER BY rolled_up_at ASC"#,
    )
    .bind(&case_id_val)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default()
    .into_iter()
    .map(|(root_id, case_id, rolled_up_at, root_hash, prev_root, leaf_count)| MerkleRootRow {
        root_id,
        case_id,
        rolled_up_at,
        root_hash,
        prev_root,
        leaf_count,
    })
    .collect();

    let mut ctx = tera::Context::new();
    ctx.insert("case_id",     &case_id_val);
    ctx.insert("case_name",   &case_name);
    ctx.insert("case_status", &case_status);
    ctx.insert("roots",       &roots);
    ctx.insert("root_count",  &roots.len());

    let body = state
        .tera
        .render("audit.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

pub async fn audit_verify(
    State(state): State<AppState>,
    Path((_case_id, root_id)): Path<(String, i64)>,
) -> Json<VerifyResult> {
    let row = sqlx::query_as::<_, (i64, String, String, i32, bool)>(
        r#"SELECT root_id, stored_hash, derived_hash, leaf_count, ok
           FROM merkle_verify($1)"#,
    )
    .bind(root_id)
    .fetch_optional(&state.pool)
    .await;

    match row {
        Ok(Some((rid, stored, derived, leaf_count, ok))) => Json(VerifyResult {
            root_id: rid,
            stored_hash: stored,
            derived_hash: derived,
            leaf_count,
            ok,
        }),
        Ok(None) => Json(VerifyResult {
            root_id,
            stored_hash: String::new(),
            derived_hash: String::new(),
            leaf_count: 0,
            ok: false,
        }),
        Err(e) => Json(VerifyResult {
            root_id,
            stored_hash: format!("error: {e}"),
            derived_hash: String::new(),
            leaf_count: 0,
            ok: false,
        }),
    }
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
