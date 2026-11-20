//! The agent against a real backend on this machine.

use std::path::Path;
use std::time::Duration;

use lep_agent::backend::{Backend, CallError};
use lep_agent::config::Config;
use lep_agent::service;
use lep_backend::app::{self, AppState};
use lep_backend::{db, game_server, worlds};
use sqlx::SqlitePool;
use tokio::net::TcpListener;

/// Starts a backend on a free port and returns its address.
async fn backend(pool: SqlitePool) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move {
        axum::serve(listener, app::router(AppState::new(pool)))
            .await
            .unwrap();
    });
    address
}

fn settings(address: &str, key: &str, folder: &Path) -> Config {
    Config::parse(&format!(
        "backend = \"{address}\"\nkey = \"{key}\"\ndata_dir = \"{}\"\n",
        folder.display()
    ))
    .unwrap()
}

#[tokio::test]
async fn the_backend_shows_what_the_agent_reports() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let address = backend(pool.clone()).await;
    let folder = tempfile::tempdir().unwrap();
    let config = settings(&address, &key, folder.path());

    service::report_once(&config, &Backend::new(&config).unwrap())
        .await
        .unwrap();

    let server = game_server::describe(&pool).await.unwrap().unwrap();
    assert!(server.connected);
    assert_eq!(server.version.as_deref(), Some(env!("CARGO_PKG_VERSION")));
    assert!(server.free_disk_bytes.unwrap() > 0);
}

#[tokio::test]
async fn a_wrong_key_is_refused() {
    let pool = db::open_in_memory().await.unwrap();
    game_server::rekey(&pool).await.unwrap();
    let (_, world_key) = worlds::add(&pool, "7b").await.unwrap();
    let address = backend(pool.clone()).await;
    let folder = tempfile::tempdir().unwrap();

    let config = settings(&address, "lepa_wrong", folder.path());
    let result = service::report_once(&config, &Backend::new(&config).unwrap()).await;
    assert_eq!(result, Err(CallError::Refused));
    // The message tells what to do and nothing about the key.
    assert!(!CallError::Refused.to_string().contains("lepa_wrong"));
    assert!(!world_key.starts_with("lepa_"));

    let server = game_server::describe(&pool).await.unwrap().unwrap();
    assert_eq!(server.last_seen_at, None);
}

#[tokio::test]
async fn a_backend_out_of_reach_is_no_reason_to_end() {
    // A port nobody listens on.
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = format!("http://{}", listener.local_addr().unwrap());
    drop(listener);
    let folder = tempfile::tempdir().unwrap();
    let config = settings(&address, "lepa_0123", folder.path());
    let backend = Backend::new(&config).unwrap();

    let result = service::report_once(&config, &backend).await;
    assert!(
        matches!(result, Err(CallError::Unreachable(_))),
        "{result:?}"
    );

    // The agent keeps running and trying until it is told to stop.
    let stop = tokio::time::sleep(Duration::from_millis(300));
    tokio::time::timeout(
        Duration::from_secs(10),
        service::run_every(&config, &backend, Duration::from_millis(50), stop),
    )
    .await
    .expect("the agent did not stop");
}

#[tokio::test]
async fn the_agent_reports_again_and_again() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let address = backend(pool.clone()).await;
    let folder = tempfile::tempdir().unwrap();
    let config = settings(&address, &key, folder.path());
    let backend = Backend::new(&config).unwrap();

    let watched = pool.clone();
    let stop = async move {
        // Wait for the first report, forget it, and wait for the next.
        for _ in 0..2 {
            loop {
                let server = game_server::describe(&watched).await.unwrap().unwrap();
                if server.last_seen_at.is_some() {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            sqlx::query("UPDATE game_server SET last_seen_at = NULL")
                .execute(&watched)
                .await
                .unwrap();
        }
    };
    tokio::time::timeout(
        Duration::from_secs(10),
        service::run_every(&config, &backend, Duration::from_millis(30), stop),
    )
    .await
    .expect("the agent did not report twice");
}
