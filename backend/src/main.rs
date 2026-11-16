use anyhow::{Context, Result};
use clap::Parser;
use lep_backend::app::{self, AppState};
use lep_backend::cli::{self, Cli, Command};
use lep_backend::config::Config;
use lep_backend::db;
use lep_backend::mail::Mailer;
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command.unwrap_or(Command::Serve) {
        Command::Serve => serve().await,
        Command::Openapi => {
            print!("{}", cli::openapi());
            Ok(())
        }
        Command::Teacher { command } => {
            let config = Config::from_env()?;
            let pool = db::open(&config.database).await?;
            let output = cli::run_teacher(&pool, command).await;
            pool.close().await;
            println!("{}", output?);
            Ok(())
        }
        Command::World { command } => {
            let config = Config::from_env()?;
            let pool = db::open(&config.database).await?;
            let output = cli::run_world(&pool, command).await;
            pool.close().await;
            println!("{}", output?);
            Ok(())
        }
    }
}

async fn serve() -> Result<()> {
    tracing_subscriber::fmt::init();

    let config = Config::from_env()?;
    let pool = db::open(&config.database).await?;
    tracing::info!(database = %config.database.display(), "database is ready");

    let listener = TcpListener::bind(config.bind)
        .await
        .with_context(|| format!("cannot listen on {}", config.bind))?;
    tracing::info!("listening on http://{}", listener.local_addr()?);

    let state = AppState::with(pool.clone(), Mailer::Terminal, &config.public_url);
    tracing::info!(
        "mail is not set up: mails are written to this terminal, links start with {}",
        config.public_url
    );
    let router = if app::has_frontend(&config.frontend) {
        tracing::info!(folder = %config.frontend.display(), "serving the frontend");
        app::router_with_frontend(state, &config.frontend)
    } else {
        tracing::info!(
            folder = %config.frontend.display(),
            "no built frontend found, serving the interface only"
        );
        app::router(state)
    };

    axum::serve(listener, router)
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
