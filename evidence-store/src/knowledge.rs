//! DFIR knowledge base — a reference corpus of incident-handling and forensics
//! domain knowledge that specialists consult for technique/artifact grounding.
//!
//!   es knowledge "<query>"        -> top-k relevant reference passages (specialist-facing)
//!   es knowledge-ingest <file>    -> chunk + embed a reference corpus (operator-facing)
//!
//! Embeddings via Ollama nomic-embed-text (768-dim, zero-padded to 1536 to match the
//! pgvector column). The corpus content is operator-provided and lives only in the local
//! database — it is never committed to the repository.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::env;
use std::time::Duration;

const EMBED_MODEL: &str = "nomic-embed-text";
const TARGET_DIMS: usize = 1536;
const CHUNK_CHARS: usize = 1200;

#[derive(Serialize)]
struct EmbedRequest<'a> { model: &'a str, input: &'a str }
#[derive(Deserialize)]
struct EmbedResponse { embeddings: Vec<Vec<f64>> }

fn ollama_url() -> String {
    env::var("OLLAMA_URL").unwrap_or_else(|_| "http://127.0.0.1:11434".into())
}

fn vec_to_pg_literal(v: &[f32]) -> String {
    format!("[{}]", v.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(","))
}

async fn embed(client: &Client, text: &str) -> Result<Vec<f32>> {
    let url = format!("{}/api/embed", ollama_url());
    let resp: EmbedResponse = client
        .post(&url)
        .json(&EmbedRequest { model: EMBED_MODEL, input: text })
        .send().await.context("POST Ollama /api/embed")?
        .error_for_status().context("Ollama non-2xx")?
        .json().await.context("parse embed response")?;
    let raw = resp.embeddings.into_iter().next().context("empty embeddings")?;
    let mut v: Vec<f32> = raw.iter().map(|&x| x as f32).collect();
    v.resize(TARGET_DIMS, 0.0);
    Ok(v)
}

fn chunk_text(s: &str, size: usize) -> Vec<String> {
    let mut chunks = Vec::new();
    let mut cur = String::new();
    for para in s.split("\n\n") {
        let p = para.trim();
        if p.is_empty() { continue; }
        if !cur.is_empty() && cur.len() + p.len() > size {
            chunks.push(std::mem::take(&mut cur));
        }
        if !cur.is_empty() { cur.push_str("\n\n"); }
        cur.push_str(p);
        if cur.len() >= size { chunks.push(std::mem::take(&mut cur)); }
    }
    if !cur.trim().is_empty() { chunks.push(cur); }
    chunks
}

pub async fn ingest(pool: &PgPool, path: &str) -> Result<()> {
    let client = Client::builder().timeout(Duration::from_secs(90)).build()?;
    let text = std::fs::read_to_string(path).with_context(|| format!("read {path}"))?;
    let source = std::path::Path::new(path)
        .file_name().and_then(|x| x.to_str()).unwrap_or("corpus").to_string();
    let chunks = chunk_text(&text, CHUNK_CHARS);
    let total = chunks.len();
    eprintln!("ingesting {total} chunks from {source}");
    let mut ok = 0usize;
    for (i, ch) in chunks.iter().enumerate() {
        match embed(&client, ch).await {
            Ok(v) => {
                sqlx::query("INSERT INTO dfir_knowledge (source, chunk, embedding) VALUES ($1, $2, $3::vector)")
                    .bind(&source).bind(ch).bind(vec_to_pg_literal(&v))
                    .execute(pool).await.context("insert chunk")?;
                ok += 1;
            }
            Err(e) => eprintln!("  embed {i} failed: {e}"),
        }
        if i % 50 == 0 { eprintln!("  {i}/{total}"); }
    }
    eprintln!("done: {ok}/{total} chunks ingested into dfir_knowledge");
    Ok(())
}

pub async fn query(pool: &PgPool, q: &str, k: i64) -> Result<()> {
    let client = Client::builder().timeout(Duration::from_secs(30)).build()?;
    let v = embed(&client, q).await?;
    let rows: Vec<(String, String, f64)> = sqlx::query_as(
        "SELECT source, chunk, 1.0 - (embedding <=> $1::vector) AS sim \
         FROM dfir_knowledge ORDER BY embedding <=> $1::vector LIMIT $2",
    )
    .bind(vec_to_pg_literal(&v))
    .bind(k)
    .fetch_all(pool).await.context("knowledge query")?;

    if rows.is_empty() {
        println!("(DFIR knowledge base empty — operator must run: es knowledge-ingest <corpus-file>)");
        return Ok(());
    }
    for (i, (src, chunk, sim)) in rows.iter().enumerate() {
        println!("=== [{}] {} (relevance {:.2}) ===", i + 1, src, sim);
        println!("{}\n", chunk.chars().take(800).collect::<String>());
    }
    Ok(())
}
