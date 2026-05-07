mod routes;

use anyhow::{Context, Result};
use axum::{routing::get, Router};
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::{env, net::SocketAddr, path::PathBuf, sync::Arc};
use tera::Tera;
use tower_http::services::ServeDir;
use tracing::info;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub tera: Arc<Tera>,
}

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();

    let pool = db_connect().await.context("connect to postgres")?;
    let tera = load_templates().context("load templates")?;

    let state = AppState {
        pool,
        tera: Arc::new(tera),
    };

    let static_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("static");

    let app = Router::new()
        .route("/ping", get(|| async { "pong" }))
        .route("/", get(routes::cases_list))
        .route("/cases/partial", get(routes::cases_list_partial))
        .route("/case/:id", get(routes::case_detail))
        .route("/case/:id/events", get(routes::case_events))
        .route("/case/:id/findings", get(routes::findings_list))
        .route("/finding/:fid", get(routes::finding_detail))
        .route("/case/:id/graph", get(routes::graph_page))
        .route("/case/:id/graph/data", get(routes::graph_data))
        .route("/case/:id/graph/node/:nid/findings", get(routes::node_findings))
        .route("/case/:id/audit", get(routes::audit_page))
        .route("/case/:id/audit/:rid/verify", get(routes::audit_verify))
        .nest_service("/static", ServeDir::new(static_dir))
        .with_state(state);

    let addr: SocketAddr = "0.0.0.0:8932".parse()?;
    info!("sleuth-saas listening on {addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn db_connect() -> Result<PgPool> {
    let url = env::var("DATABASE_URL").unwrap_or_else(|_| {
        let host = env::var("PG_HOST").unwrap_or_else(|_| "127.0.0.1".into());
        let port = env::var("PG_PORT").unwrap_or_else(|_| "5532".into());
        let db   = env::var("PG_DB").unwrap_or_else(|_| "sleuth".into());
        let user = env::var("PG_USER").unwrap_or_else(|_| "sleuth".into());
        let pw   = env::var("PG_PASSWORD").unwrap_or_else(|_| "changeme-dev-only".into());
        format!("postgres://{user}:{pw}@{host}:{port}/{db}")
    });
    PgPoolOptions::new()
        .max_connections(4)
        .connect(&url)
        .await
        .context("postgres connect")
}

fn load_templates() -> Result<Tera> {
    let tmpl_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("templates");
    let glob = format!("{}/**/*.html", tmpl_dir.display());
    let tera = Tera::new(&glob).context("init tera")?;
    Ok(tera)
}

fn init_tracing() {
    let level = env::var("RUST_LOG").unwrap_or_else(|_| "info".into());
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::new(level))
        .with_target(false)
        .compact()
        .init();
}
