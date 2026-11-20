//! The agent against a real backend on this machine.

use std::path::Path;
use std::time::Duration;

use lep_agent::backend::{Backend, CallError};
use lep_agent::config::Config;
use lep_agent::service::{self, Agent, Prepared, Timing};
use lep_agent::template::Manifest;
use lep_backend::app::{self, AppState};
use lep_backend::{db, game_server, jobs, worlds};
use lep_protocol::agent::{CreateWorld, JOB_CREATE_WORLD};
use sqlx::SqlitePool;
use tokio::net::TcpListener;

const TEMPLATE: &str = "bdbbf00c8a29";

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

/// An agent with a template and an admin, as on a server that is set up.
fn agent(address: &str, key: &str, folder: &Path) -> Agent {
    let config = Config::parse(&format!(
        "backend = \"{address}\"\nkey = \"{key}\"\ndata_dir = \"{}\"\n\
         admin = \"peddn\"\nports = \"30000-30001\"\n",
        folder.display()
    ))
    .unwrap();
    let manifest = Manifest::parse(
        "lep_mods = [\"lep_core\", \"lep_bridge\"]\n[[mods]]\nname = \"protector\"\n",
    )
    .unwrap();
    Agent {
        config,
        template: Some(Prepared {
            version: TEMPLATE.to_owned(),
            manifest,
        }),
    }
}

/// Short times, so the tests need no patience.
fn quick() -> Timing {
    Timing {
        report: Duration::from_millis(40),
        job_wait: Duration::from_secs(1),
        retry: Duration::from_millis(40),
    }
}

/// Runs the agent until `done` says so, at most ten seconds.
async fn run_until(agent: &Agent, done: impl std::future::Future<Output = ()>) {
    let backend = Backend::new(&agent.config).unwrap();
    tokio::time::timeout(
        Duration::from_secs(10),
        service::run_with(agent, &backend, quick(), done),
    )
    .await
    .expect("the agent did not get there in time");
}

/// Puts a world into the backend and the job to create it.
async fn order_world(pool: &SqlitePool, name: &str) -> (worlds::World, String) {
    let (world, key) = worlds::add(pool, name).await.unwrap();
    let payload = serde_json::to_value(CreateWorld {
        world: world.id.clone(),
        bridge_key: key,
    })
    .unwrap();
    let job = jobs::add_for_agent(pool, &world.id, JOB_CREATE_WORLD, &payload)
        .await
        .unwrap();
    (world, job)
}

async fn finished(pool: &SqlitePool, job: &str) -> bool {
    jobs::state(pool, job).await.unwrap().unwrap().finished
}

#[tokio::test]
async fn the_backend_shows_what_the_agent_reports() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let address = backend(pool.clone()).await;
    let folder = tempfile::tempdir().unwrap();
    let agent = agent(&address, &key, folder.path());

    service::report_once(&agent, &Backend::new(&agent.config).unwrap())
        .await
        .unwrap();

    let server = game_server::describe(&pool).await.unwrap().unwrap();
    assert!(server.connected);
    assert_eq!(server.version.as_deref(), Some(env!("CARGO_PKG_VERSION")));
    assert!(server.free_disk_bytes.unwrap() > 0);
    assert_eq!(server.template.as_deref(), Some(TEMPLATE));
}

#[tokio::test]
async fn a_wrong_key_is_refused() {
    let pool = db::open_in_memory().await.unwrap();
    game_server::rekey(&pool).await.unwrap();
    let address = backend(pool.clone()).await;
    let folder = tempfile::tempdir().unwrap();
    let agent = agent(&address, "lepa_wrong", folder.path());
    let backend = Backend::new(&agent.config).unwrap();

    let result = service::report_once(&agent, &backend).await;
    assert_eq!(result, Err(CallError::Refused));
    // The message tells what to do and nothing about the key.
    assert!(!CallError::Refused.to_string().contains("lepa_wrong"));
    let jobs = backend.fetch_jobs(Duration::ZERO).await;
    assert_eq!(jobs, Err(CallError::Refused));

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
    let agent = agent(&address, "lepa_0123", folder.path());

    let result = service::report_once(&agent, &Backend::new(&agent.config).unwrap()).await;
    assert!(
        matches!(result, Err(CallError::Unreachable(_))),
        "{result:?}"
    );
    // The agent keeps running and trying until it is told to stop.
    run_until(&agent, tokio::time::sleep(Duration::from_millis(300))).await;
}

#[tokio::test]
async fn the_agent_reports_again_and_again() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let address = backend(pool.clone()).await;
    let folder = tempfile::tempdir().unwrap();
    let agent = agent(&address, &key, folder.path());

    let watched = pool.clone();
    run_until(&agent, async move {
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
    })
    .await;
}

#[tokio::test]
async fn the_agent_creates_the_world_the_backend_orders() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let address = backend(pool.clone()).await;
    let folder = tempfile::tempdir().unwrap();
    let agent = agent(&address, &key, folder.path());
    let (world, job) = order_world(&pool, "7b").await;

    // Until the backend knows the port: the job is done and reported.
    let watched = pool.clone();
    run_until(&agent, async move {
        loop {
            let all = worlds::list(&watched).await.unwrap();
            if all[0].port.is_some() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await;

    let state = jobs::state(&pool, &job).await.unwrap().unwrap();
    assert_eq!(state.ok, Some(true));
    assert_eq!(state.message.as_deref(), Some("created on port 30000"));
    let mirrored = worlds::find_by_name(&pool, "7b").await.unwrap().unwrap();
    assert_eq!(mirrored.port, Some(30000));
    assert_eq!(mirrored.template_version.as_deref(), Some(TEMPLATE));

    // The world lies in its folder, and its bridge calls with a key the
    // backend takes for exactly this world.
    let settings = folder
        .path()
        .join("worlds")
        .join(&world.id)
        .join("minetest.conf");
    let text = std::fs::read_to_string(settings).unwrap();
    assert!(text.contains(&format!("lep_bridge_url = {address}\n")));
    let bridge_key = text
        .lines()
        .find_map(|line| line.strip_prefix("lep_bridge_key = "))
        .unwrap();
    let found = worlds::find_by_key(&pool, bridge_key)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(found.id, world.id);

    // Once the job is answered, the key is gone from the database.
    let stored: String = sqlx::query_scalar("SELECT payload FROM jobs WHERE id = ?")
        .bind(&job)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(!stored.contains(bridge_key));
}

#[tokio::test]
async fn a_job_the_agent_cannot_do_is_refused_and_reported() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let address = backend(pool.clone()).await;
    let folder = tempfile::tempdir().unwrap();
    let agent = agent(&address, &key, folder.path());

    // Two ports, three worlds, and a job of a kind nobody knows.
    let (_, first) = order_world(&pool, "7a").await;
    let (_, second) = order_world(&pool, "7b").await;
    let (third_world, third) = order_world(&pool, "7c").await;
    let unknown = jobs::add_for_agent(
        &pool,
        &third_world.id,
        "run_command",
        &serde_json::json!({}),
    )
    .await
    .unwrap();

    let watched = pool.clone();
    let last = unknown.clone();
    run_until(&agent, async move {
        while !finished(&watched, &last).await {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await;

    for job in [&first, &second] {
        assert_eq!(
            jobs::state(&pool, job).await.unwrap().unwrap().ok,
            Some(true)
        );
    }
    let full = jobs::state(&pool, &third).await.unwrap().unwrap();
    assert_eq!(full.ok, Some(false));
    assert!(full.message.unwrap().contains("no port is free"));
    let refused = jobs::state(&pool, &unknown).await.unwrap().unwrap();
    assert_eq!(refused.ok, Some(false));
    assert!(refused.message.unwrap().contains("does not know"));

    assert!(!folder.path().join("worlds").join(&third_world.id).exists());
    assert_eq!(
        std::fs::read_dir(folder.path().join("worlds"))
            .unwrap()
            .count(),
        2
    );
}
