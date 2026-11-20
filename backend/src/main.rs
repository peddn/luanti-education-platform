use anyhow::{Context, Result};
use clap::Parser;
use lep_backend::app::{self, AppState};
use lep_backend::cli::{self, Cli, Command};
use lep_backend::config::Config;
use lep_backend::mail::Mailer;
use lep_backend::{clock, db, logins};
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
        Command::Mail { command } => {
            let config = Config::from_env()?;
            println!("{}", cli::run_mail(&config, command).await?);
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
        Command::Agent { command } => {
            let config = Config::from_env()?;
            let pool = db::open(&config.database).await?;
            let output = cli::run_agent(&pool, command).await;
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

    let mailer = Mailer::from_settings(config.smtp.as_ref())?;
    match &config.smtp {
        Some(smtp) => tracing::info!(
            "mails are sent through {}:{} as {}, links start with {}",
            smtp.host,
            smtp.port,
            smtp.from,
            config.public_url
        ),
        None => tracing::info!(
            "no mail server is set: mails are written to this terminal, links start with {}",
            config.public_url
        ),
    }
    let state = AppState::with(pool.clone(), mailer, &config.public_url);
    let changes = state.changes.clone();
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

    tokio::spawn(clean_up_hourly(pool.clone()));

    axum::serve(listener, router)
        .with_graceful_shutdown(async move {
            shutdown().await;
            // Requests that are kept open would hold the backend up:
            // worlds waiting for jobs, pages waiting for changes.
            changes.stop();
        })
        .await?;

    pool.close().await;
    tracing::info!("stopped");
    Ok(())
}

/// Deletes login links and sessions whose time is over: at the start and
/// every hour after.
async fn clean_up_hourly(pool: sqlx::SqlitePool) {
    let mut hourly = tokio::time::interval(std::time::Duration::from_secs(60 * 60));
    loop {
        hourly.tick().await;
        match logins::clean_up(&pool, clock::now()).await {
            Ok(0) => {}
            Ok(count) => tracing::info!("deleted {count} old login link(s) and session(s)"),
            Err(err) => tracing::error!("cannot delete old login links and sessions: {err:#}"),
        }
    }
}

/// Resolves when the process is asked to stop with Ctrl+C.
async fn shutdown() {
    if let Err(err) = tokio::signal::ctrl_c().await {
        tracing::error!("cannot wait for Ctrl+C: {err}");
    }
}
