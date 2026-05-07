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
        .route("/", get(routes::index))
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
