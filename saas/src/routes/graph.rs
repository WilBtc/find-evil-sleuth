use axum::{
    extract::{Path, Query, State},
    response::{Html, Json},
};
use serde::{Deserialize, Serialize};
use crate::AppState;

#[derive(Debug, Serialize, Deserialize)]
pub struct GraphNode {
    pub id:    String,
    pub label: String,
    pub group: String,
    pub props: serde_json::Value,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GraphEdge {
    pub id:    String,
    pub from:  String,
    pub to:    String,
    pub label: String,
}

#[derive(Debug, Serialize)]
pub struct GraphData {
    pub nodes: Vec<GraphNode>,
    pub edges: Vec<GraphEdge>,
}

pub async fn graph_page(
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

    let mut ctx = tera::Context::new();
    ctx.insert("case_id",     &case_id_val);
    ctx.insert("case_name",   &case_name);
    ctx.insert("case_status", &case_status);

    let body = state
        .tera
        .render("graph.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

pub async fn graph_data(
    State(state): State<AppState>,
    Path(_case_id): Path<String>,
) -> Json<GraphData> {
    let nodes = query_nodes(&state).await;
    let edges = query_edges(&state).await;
    Json(GraphData { nodes, edges })
}

async fn query_nodes(state: &AppState) -> Vec<GraphNode> {
    let node_labels = [
        "Process",
        "File",
        "NetworkEndpoint",
        "RegistryKey",
        "User",
        "IOC",
    ];
    let mut out: Vec<GraphNode> = Vec::new();

    for label in node_labels {
        let sql = format!(
            r#"SELECT id::text, properties::text
               FROM case_graph."{label}"
               WHERE properties::text != 'null'
               LIMIT 500"#,
            label = label
        );

        let rows: Vec<(String, String)> = match sqlx::query_as::<_, (String, String)>(&sql)
            .fetch_all(&state.pool)
            .await
        {
            Ok(r) => r,
            Err(_) => continue,
        };

        for (id_str, props_str) in rows {
            let props: serde_json::Value = serde_json::from_str(&props_str)
                .unwrap_or(serde_json::json!({}));

            if props.get("_init").is_some() {
                continue;
            }

            let display = extract_node_label(label, &props);

            out.push(GraphNode {
                id:    id_str.trim().to_string(),
                label: display,
                group: label.to_string(),
                props,
            });
        }
    }

    out
}

async fn query_edges(state: &AppState) -> Vec<GraphEdge> {
    let edge_labels = [
        "SPAWNED",
        "WROTE",
        "READ",
        "LOADED",
        "CONNECTED_TO",
        "LOGGED_IN_AS",
        "MATCHED",
    ];
    let mut out: Vec<GraphEdge> = Vec::new();

    for edge_label in edge_labels {
        let sql = format!(
            r#"SELECT id::text, start_id::text, end_id::text
               FROM case_graph."{edge_label}"
               LIMIT 1000"#,
            edge_label = edge_label
        );

        let rows: Vec<(String, String, String)> =
            match sqlx::query_as::<_, (String, String, String)>(&sql)
                .fetch_all(&state.pool)
                .await
            {
                Ok(r) => r,
                Err(_) => continue,
            };

        for (eid, src, dst) in rows {
            out.push(GraphEdge {
                id:    eid.trim().to_string(),
                from:  src.trim().to_string(),
                to:    dst.trim().to_string(),
                label: edge_label.to_string(),
            });
        }
    }

    out
}

fn extract_node_label(node_type: &str, props: &serde_json::Value) -> String {
    match node_type {
        "Process" => {
            let name = props.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let pid  = props.get("pid").and_then(|v| v.as_i64());
            if let Some(p) = pid {
                format!("{name}\n(PID {p})")
            } else {
                name.to_string()
            }
        }
        "File" | "RegistryKey" => {
            let path = props.get("path")
                .or_else(|| props.get("name"))
                .and_then(|v| v.as_str())
                .unwrap_or(node_type);
            let short = path.rsplit(['/', '\\']).next().unwrap_or(path);
            if short.is_empty() { path.to_string() } else { short.to_string() }
        }
        "NetworkEndpoint" => {
            let ip   = props.get("ip").and_then(|v| v.as_str()).unwrap_or("");
            let port = props.get("port").and_then(|v| v.as_i64());
            if let Some(p) = port { format!("{ip}:{p}") } else { ip.to_string() }
        }
        "User" => props.get("name").and_then(|v| v.as_str()).unwrap_or("User").to_string(),
        "IOC"  => props.get("value").or_else(|| props.get("name"))
                       .and_then(|v| v.as_str()).unwrap_or("IOC").to_string(),
        _ => node_type.to_string(),
    }
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

#[derive(Debug, Serialize)]
pub struct FindingRef {
    pub finding_id:        String,
    pub claim:             String,
    pub specialist:        String,
    pub validation_status: String,
}

#[derive(Debug, Deserialize)]
pub struct NodeFindingsQuery {
    pub q: Option<String>,
}

pub async fn node_findings(
    State(state): State<AppState>,
    Path((case_id, _nid)): Path<(String, String)>,
    Query(params): Query<NodeFindingsQuery>,
) -> Json<Vec<FindingRef>> {
    let search = params.q.unwrap_or_default();
    if search.is_empty() {
        return Json(Vec::new());
    }

    let rows: Vec<FindingRef> = sqlx::query_as::<_, (String, String, String, String)>(
        r#"SELECT finding_id, claim, specialist, validation_status
           FROM findings
           WHERE case_id = $1
             AND claim ILIKE '%' || $2 || '%'
           ORDER BY finding_id ASC
           LIMIT 20"#,
    )
    .bind(&case_id)
    .bind(&search)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default()
    .into_iter()
    .map(|(finding_id, claim, specialist, validation_status)| FindingRef {
        finding_id,
        claim,
        specialist,
        validation_status,
    })
    .collect();

    Json(rows)
}
