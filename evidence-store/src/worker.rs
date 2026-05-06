//! Embedding worker — `es worker --embeddings`
//!
//! Listens on Postgres NOTIFY channel "embed_findings".
//! For each notified finding_id:
//!   1. Fetch the claim text.
//!   2. Call Ollama nomic-embed-text to get a 768-dim vector.
//!   3. Zero-pad to 1536 dims (pgvector column size).
//!   4. Write back to findings.embedding.
//!   5. If cosine_distance < 0.08 to any existing embedding, set superseded_by.
//!
//! Ollama endpoint: env OLLAMA_URL (default http://100.116.33.91:11434)

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::env;
use std::time::Duration;
use tokio::time::sleep;
use tracing::{error, info, warn};

const CHANNEL: &str = "embed_findings";
const BATCH_WAIT: Duration = Duration::from_secs(5);
const COSINE_DUP_THRESHOLD: f64 = 0.08;
const EMBED_MODEL: &str = "nomic-embed-text";
const TARGET_DIMS: usize = 1536;

#[derive(Serialize)]
struct EmbedRequest<'a> {
    model: &'a str,
    input: &'a str,
}

#[derive(Deserialize)]
struct EmbedResponse {
    embeddings: Vec<Vec<f64>>,
}

fn ollama_url() -> String {
    env::var("OLLAMA_URL").unwrap_or_else(|_| "http://100.116.33.91:11434".into())
}

fn vec_to_pg_literal(v: &[f32]) -> String {
    let inner: Vec<String> = v.iter().map(|x| x.to_string()).collect();
    format!("[{}]", inner.join(","))
}

async fn embed(client: &Client, text: &str) -> Result<Vec<f32>> {
    let url = format!("{}/api/embed", ollama_url());
    let body = EmbedRequest { model: EMBED_MODEL, input: text };
    let resp: EmbedResponse = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .context("POST to Ollama /api/embed")?
        .error_for_status()
        .context("Ollama returned non-2xx")?
        .json()
        .await
        .context("parse Ollama embed response")?;

    let raw = resp
        .embeddings
        .into_iter()
        .next()
        .context("empty embeddings array from Ollama")?;
    let mut vec: Vec<f32> = raw.iter().map(|&x| x as f32).collect();
    vec.resize(TARGET_DIMS, 0.0);
    Ok(vec)
}

async fn process_finding(pool: &PgPool, client: &Client, finding_id: &str) -> Result<()> {
    let row: Option<(String,)> =
        sqlx::query_as("SELECT claim FROM findings WHERE finding_id = $1")
            .bind(finding_id)
            .fetch_optional(pool)
            .await?;

    let claim = match row {
        Some((c,)) => c,
        None => {
            warn!(%finding_id, "finding not found, skipping embed");
            return Ok(());
        }
    };

    let embedding = embed(client, &claim)
        .await
        .with_context(|| format!("embed finding {finding_id}"))?;

    let vec_literal = vec_to_pg_literal(&embedding);

    let near: Option<(String,)> = sqlx::query_as(
        r#"SELECT finding_id
             FROM findings
            WHERE embedding IS NOT NULL
              AND finding_id <> $1
              AND (embedding <=> $2::vector) < $3
            ORDER BY embedding <=> $2::vector
            LIMIT 1"#,
    )
    .bind(finding_id)
    .bind(&vec_literal)
    .bind(COSINE_DUP_THRESHOLD)
    .fetch_optional(pool)
    .await?;

    if let Some((dup_id,)) = near {
        warn!(%finding_id, %dup_id, "duplicate finding (cosine < threshold); marking superseded");
        sqlx::query("UPDATE findings SET superseded_by = $1 WHERE finding_id = $2")
            .bind(&dup_id)
            .bind(finding_id)
            .execute(pool)
            .await?;
    }

    sqlx::query("UPDATE findings SET embedding = $1::vector WHERE finding_id = $2")
        .bind(&vec_literal)
        .bind(finding_id)
        .execute(pool)
        .await?;

    info!(%finding_id, dims = TARGET_DIMS, "embedding written");
    Ok(())
}

pub async fn run(pool: PgPool) -> Result<()> {
    info!("embedding worker starting; listening on channel '{CHANNEL}'");

    let mut listener = sqlx::postgres::PgListener::connect_with(&pool)
        .await
        .context("create PgListener")?;
    listener.listen(CHANNEL).await.context("LISTEN embed_findings")?;

    let client = Client::builder()
        .timeout(Duration::from_secs(60))
        .build()
        .context("build reqwest client")?;

    let mut pending: Vec<String> = Vec::new();

    loop {
        tokio::select! {
            notification = listener.recv() => {
                match notification {
                    Ok(n) => {
                        let id = n.payload().to_string();
                        info!(%id, "queued for embedding");
                        pending.push(id);
                    }
                    Err(e) => {
                        error!("listener error: {e:#}; reconnecting in 5s");
                        sleep(Duration::from_secs(5)).await;
                        listener.listen(CHANNEL).await.ok();
                    }
                }
            }
            _ = sleep(BATCH_WAIT), if !pending.is_empty() => {
                let batch = std::mem::take(&mut pending);
                info!(count = batch.len(), "processing embedding batch");
                for id in &batch {
                    if let Err(e) = process_finding(&pool, &client, id).await {
                        error!(%id, "embed failed: {e:#}");
                    }
                }
            }
        }
    }
}
