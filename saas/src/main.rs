mod routes;

use anyhow::{Context, Result};
use axum::{
    response::Redirect,
    routing::{get, post},
    Router,
};
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::{env, net::SocketAddr, path::PathBuf, sync::Arc, time::Duration};
use tera::Tera;
use tower_http::services::ServeDir;
use tracing::{info, warn};

const LONE_WOLF_CASE: &str = "lone-wolf-1778168581";
const THEATRE_TOGGLE: &str = "/.sleuth-saas-theatre";

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
        pool: pool.clone(),
        tera: Arc::new(tera),
    };

    tokio::spawn(theatre_cron(pool));

    let static_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("static");

    let app = Router::new()
        .route("/ping", get(|| async { "pong" }))
        .route(
            "/",
            get(|| async { Redirect::temporary("/cases") }),
        )
        .route("/cases", get(routes::cases_list))
        .route("/cases/partial", get(routes::cases_list_partial))
        .route("/cases/new", post(routes::new_case))
        .route("/case/:id/log", get(routes::case_log_tail))
        .route("/case/:id", get(routes::case_detail))
        .route("/case/:id/events", get(routes::case_events))
        .route("/case/:id/findings", get(routes::findings_list))
        .route("/finding/:fid", get(routes::finding_detail))
        .route("/finding/:fid/drawer", get(routes::finding_drawer))
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

async fn theatre_cron(pool: PgPool) {
    let toggle = home_path(THEATRE_TOGGLE);
    let mut interval = tokio::time::interval(Duration::from_secs(60));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        interval.tick().await;
        if !toggle.exists() {
            continue;
        }
        match insert_theatre_tool_call(&pool).await {
            Ok(id) => info!(tool_call_id = %id, "theatre: inserted live tool_call"),
            Err(e) => warn!("theatre: failed to insert tool_call: {e}"),
        }
    }
}

async fn insert_theatre_tool_call(pool: &PgPool) -> Result<String> {
    let row: (String,) = sqlx::query_as(
        r#"
        INSERT INTO tool_calls
            (case_id, tool, args, exit_code, duration_ms, is_validation)
        VALUES
            ($1, 'fls', '{"image":"/case/LoneWolf.E01","extra_args":["-r","-l"]}', 0, 420, true)
        RETURNING tool_call_id::text
        "#,
    )
    .bind(LONE_WOLF_CASE)
    .fetch_one(pool)
    .await
    .context("insert theatre tool_call")?;
    Ok(row.0)
}

fn home_path(suffix: &str) -> PathBuf {
    let home = env::var("HOME").unwrap_or_else(|_| "/root".into());
    PathBuf::from(home).join(suffix.trim_start_matches('/'))
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
