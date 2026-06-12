use axum::{
    extract::{Path, State},
    response::{Html, Sse},
};
use axum::response::sse::Event;
use futures_util::stream::Stream;
use serde::Serialize;
use sqlx::FromRow;
use std::{convert::Infallible, pin::Pin, time::Duration};
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use crate::AppState;

#[derive(Debug, Serialize, FromRow)]
pub struct CaseDetail {
    pub case_id:     String,
    pub name:        String,
    pub started_at:  chrono::DateTime<chrono::Utc>,
    pub finished_at: Option<chrono::DateTime<chrono::Utc>>,
    pub status:      String,
}

#[derive(Debug, Serialize, FromRow)]
pub struct ToolCallRow {
    pub tool_call_id: String,
    pub started_at:   chrono::DateTime<chrono::Utc>,
    pub finished_at:  Option<chrono::DateTime<chrono::Utc>>,
    pub tool:         String,
    pub exit_code:    Option<i32>,
    pub duration_ms:  Option<i32>,
    pub is_validation: bool,
}

#[derive(Debug, Serialize, FromRow)]
pub struct SelfCorrectionRow {
    pub attempt_id:     String,
    pub failed_tool:    String,
    pub failed_exit:    i32,
    pub retry_strategy: String,
    pub retry_tool:     String,
    pub succeeded:      Option<bool>,
    pub created_at:     chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "kind")]
pub enum TimelineEntry {
    #[serde(rename = "tool_call")]
    ToolCall(ToolCallRow),
    #[serde(rename = "correction")]
    Correction(SelfCorrectionRow),
}

impl TimelineEntry {
    fn timestamp(&self) -> chrono::DateTime<chrono::Utc> {
        match self {
            TimelineEntry::ToolCall(tc) => tc.started_at,
            TimelineEntry::Correction(sc) => sc.created_at,
        }
    }
}

pub async fn case_detail(
    State(state): State<AppState>,
    Path(case_id): Path<String>,
) -> Html<String> {
    let case = sqlx::query_as::<_, CaseDetail>(
        "SELECT case_id, name, started_at, finished_at, status FROM cases WHERE case_id = $1",
    )
    .bind(&case_id)
    .fetch_optional(&state.pool)
    .await;

    let case = match case {
        Ok(Some(c)) => c,
        Ok(None) => {
            return Html(format!(
                "<pre>Case '{}' not found</pre>",
                html_escape(&case_id)
            ));
        }
        Err(e) => return Html(format!("<pre>DB error: {e}</pre>")),
    };

    let tool_calls = sqlx::query_as::<_, ToolCallRow>(
        r#"
        SELECT
            tool_call_id::text,
            started_at,
            finished_at,
            tool,
            exit_code,
            duration_ms,
            is_validation
        FROM tool_calls
        WHERE case_id = $1 AND is_validation = false
        ORDER BY started_at ASC
        LIMIT 200
        "#,
    )
    .bind(&case_id)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let corrections = sqlx::query_as::<_, SelfCorrectionRow>(
        r#"
        SELECT
            attempt_id::text,
            failed_tool,
            failed_exit,
            retry_strategy,
            retry_tool,
            succeeded,
            created_at
        FROM self_corrections
        WHERE case_id = $1
        ORDER BY created_at ASC
        "#,
    )
    .bind(&case_id)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let tc_count = tool_calls.len();
    let sc_count = corrections.len();

    let mut timeline: Vec<TimelineEntry> = Vec::with_capacity(tc_count + sc_count);
    for tc in tool_calls {
        timeline.push(TimelineEntry::ToolCall(tc));
    }
    for sc in corrections {
        timeline.push(TimelineEntry::Correction(sc));
    }
    timeline.sort_by_key(|e| e.timestamp());

    let (confirmed_count, findings_count): (i64, i64) = sqlx::query_as(
        "SELECT count(*) FILTER (WHERE validation_status = 'confirmed'), count(*) FROM findings WHERE case_id = $1",
    )
    .bind(&case_id)
    .fetch_one(&state.pool)
    .await
    .unwrap_or((0, 0));

    let mut ctx = tera::Context::new();
    ctx.insert("case", &case);
    ctx.insert("timeline", &timeline);
    ctx.insert("tool_call_count", &tc_count);
    ctx.insert("correction_count", &sc_count);
    ctx.insert("confirmed_count", &confirmed_count);
    ctx.insert("findings_count", &findings_count);

    let body = state
        .tera
        .render("case_detail.html", &ctx)
        .unwrap_or_else(|e| format!("<pre>template error: {e}</pre>"));
    Html(body)
}

pub async fn case_events(
    State(state): State<AppState>,
    Path(case_id): Path<String>,
) -> Sse<Pin<Box<dyn Stream<Item = Result<Event, Infallible>> + Send>>> {
    let pool = state.pool.clone();
    let (tx, rx) = mpsc::channel::<Result<Event, Infallible>>(32);

    // Send an immediate "hello" so the browser's EventSource fires onopen
    // and the UI flips from "connecting…" to "live" right away. Without this,
    // the connection waits silently for the first NOTIFY which may never come.
    let _ = tx
        .try_send(Ok(Event::default().event("hello").data("connected")));

    tokio::spawn(async move {
        let mut listener = match sqlx::postgres::PgListener::connect_with(&pool).await {
            Ok(l) => l,
            Err(e) => {
                let _ = tx
                    .send(Ok(Event::default().event("error").data(e.to_string())))
                    .await;
                return;
            }
        };

        if let Err(e) = listener
            .listen_all(["tool_calls", "self_corrections", "findings"])
            .await
        {
            let _ = tx
                .send(Ok(Event::default().event("error").data(e.to_string())))
                .await;
            return;
        }

        loop {
            match listener.recv().await {
                Ok(notification) => {
                    let payload = notification.payload().to_string();
                    let event = Event::default()
                        .event(notification.channel())
                        .data(payload);
                    if tx.send(Ok(event)).await.is_err() {
                        break;
                    }
                }
                Err(e) => {
                    let _ = tx
                        .send(Ok(Event::default().event("error").data(e.to_string())))
                        .await;
                    break;
                }
            }
        }
    });

    let _ = case_id;

    let stream: Pin<Box<dyn Stream<Item = Result<Event, Infallible>> + Send>> =
        Box::pin(ReceiverStream::new(rx));

    Sse::new(stream).keep_alive(
        axum::response::sse::KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("ping"),
    )
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
