use anyhow::{Context, Result};
use lep_backend::app::{self, AppState};
use lep_backend::config::Config;
use lep_backend::db;
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let config = Config::from_env()?;
    let pool = db::open(&config.database).await?;
    tracing::info!(database = %config.database.display(), "database is ready");

    let listener = TcpListener::bind(config.bind)
        .await
        .with_context(|| format!("cannot listen on {}", config.bind))?;
    tracing::info!("listening on http://{}", listener.local_addr()?);

    axum::serve(listener, app::router(AppState { db: pool.clone() }))
        .with_graceful_shutdown(shutdown())
        .await?;

    pool.close().await;
    tracing::info!("stopped");
    Ok(())
}

/// Resolves when the process is asked to stop with Ctrl+C.
async fn shutdown() {
    if let Err(err) = tokio::signal::ctrl_c().await {
        tracing::error!("cannot wait for Ctrl+C: {err}");
    }
}
