use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use lep_agent::backend::Backend;
use lep_agent::config::{self, Config};
use lep_agent::service;

#[derive(Debug, Parser)]
#[command(
    name = "lep-agent",
    version,
    about = "Agent of the Luanti Education Platform"
)]
struct Cli {
    /// File with the settings.
    #[arg(long, global = true, default_value = config::DEFAULT_PATH)]
    config: PathBuf,
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Run until stopped. This is what happens without a command.
    Run,
    /// Read the settings, send one report to the backend and say how it
    /// went.
    Check,
}

#[tokio::main]
async fn main() -> ExitCode {
    let cli = Cli::parse();
    let result = match cli.command.unwrap_or(Command::Run) {
        Command::Run => run(&cli.config).await,
        Command::Check => check(&cli.config).await,
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("lep-agent: {err:#}");
            ExitCode::FAILURE
        }
    }
}

fn prepare(path: &std::path::Path) -> Result<(Config, Backend)> {
    let config = Config::read(path)?;
    std::fs::create_dir_all(&config.data_dir)
        .with_context(|| format!("cannot use the folder {}", config.data_dir.display()))?;
    let backend = Backend::new(&config)?;
    Ok((config, backend))
}

async fn run(path: &std::path::Path) -> Result<()> {
    tracing_subscriber::fmt::init();
    let (config, backend) = prepare(path)?;
    if config::is_open_to_others(path) {
        tracing::warn!(
            "{} can be read by other users, and it holds the key. Close it with: chmod 600",
            path.display()
        );
    }
    tracing::info!(
        backend = %config.backend,
        folder = %config.data_dir.display(),
        "agent {} started",
        lep_agent::report::VERSION
    );
    service::run(&config, &backend, shutdown()).await;
    tracing::info!("stopped");
    Ok(())
}

async fn check(path: &std::path::Path) -> Result<()> {
    let (config, backend) = prepare(path)?;
    println!("Settings: {}", path.display());
    println!("Backend:  {}", config.backend);
    println!("Folder:   {}", config.data_dir.display());
    if config::is_open_to_others(path) {
        println!("Warning:  other users can read the settings, and they hold the key.");
    }
    service::report_once(&config, &backend).await?;
    println!("The backend took the report.");
    Ok(())
}

/// Waits until the program is asked to end: Ctrl+C in a terminal, or the
/// signal systemd sends.
async fn shutdown() {
    let interrupt = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(_) => std::future::pending::<()>().await,
        }
    };
    tokio::select! {
        () = interrupt => {}
        () = terminate => {}
    }
}
