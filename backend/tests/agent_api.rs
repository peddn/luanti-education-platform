//! The interface for the agent, called without a network.

use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::{db, game_server, jobs, worlds};
use serde_json::{json, Value};
use tower::ServiceExt;

async fn call(
    state: &AppState,
    method: Method,
    path: &str,
    key: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut request = Request::builder().method(method).uri(path);
    if let Some(key) = key {
        request = request.header(header::AUTHORIZATION, format!("Bearer {key}"));
    }
    let body = match body {
        Some(json) => {
            request = request.header(header::CONTENT_TYPE, "application/json");
            Body::from(json.to_string())
        }
        None => Body::empty(),
    };
    let response = app::router(state.clone())
        .oneshot(request.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

fn report() -> Value {
    json!({ "version": "0.1.0", "free_disk_bytes": 12_000_000_000u64 })
}

const REPORT: &str = "/api/agent/v1/report";

#[tokio::test]
async fn the_agent_reports_with_its_key() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let state = AppState::new(pool.clone());

    let (status, _) = call(&state, Method::POST, REPORT, Some(&key), Some(report())).await;
    assert_eq!(status, StatusCode::OK);

    let server = game_server::describe(&pool).await.unwrap().unwrap();
    assert!(server.connected);
    assert_eq!(server.version.as_deref(), Some("0.1.0"));
    assert_eq!(server.free_disk_bytes, Some(12_000_000_000));
    // An agent of the first version says nothing about a template.
    assert_eq!(server.template, None);

    let with_template = json!({
        "version": "0.1.0",
        "free_disk_bytes": 1,
        "template": "BDBBF00C8A29",
    });
    let (status, _) = call(
        &state,
        Method::POST,
        REPORT,
        Some(&key),
        Some(with_template),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let server = game_server::describe(&pool).await.unwrap().unwrap();
    assert_eq!(server.template.as_deref(), Some("bdbbf00c8a29"));
}

#[tokio::test]
async fn nobody_reports_without_the_key_of_the_agent() {
    let pool = db::open_in_memory().await.unwrap();
    let state = AppState::new(pool.clone());

    // Before there is a key, no key fits.
    let (status, json) = call(&state, Method::POST, REPORT, Some("lepa_x"), Some(report())).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(json["code"], "unauthorized");

    let key = game_server::rekey(&pool).await.unwrap();
    let (_, world_key) = worlds::add(&pool, "7b").await.unwrap();

    let (status, _) = call(&state, Method::POST, REPORT, None, Some(report())).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = call(&state, Method::POST, REPORT, Some("wrong"), Some(report())).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // The key of a world does not open the interface of the agent.
    let (status, _) = call(
        &state,
        Method::POST,
        REPORT,
        Some(&world_key),
        Some(report()),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let server = game_server::describe(&pool).await.unwrap().unwrap();
    assert_eq!(server.last_seen_at, None);

    // An old key stops working with a new one.
    game_server::rekey(&pool).await.unwrap();
    let (status, _) = call(&state, Method::POST, REPORT, Some(&key), Some(report())).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn the_key_of_the_agent_opens_nothing_else() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    worlds::add(&pool, "7b").await.unwrap();
    let state = AppState::new(pool);

    let (status, _) = call(&state, Method::GET, "/api/world/v1/jobs", Some(&key), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = call(&state, Method::GET, "/api/web/v1/status", Some(&key), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = call(&state, Method::GET, "/api/web/v1/groups", Some(&key), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn the_agent_fetches_its_jobs_and_reports_how_they_went() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let (world, world_key) = worlds::add(&pool, "7b").await.unwrap();
    let state = AppState::new(pool.clone());
    const JOBS: &str = "/api/agent/v1/jobs";

    let (status, json) = call(&state, Method::GET, JOBS, Some(&key), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["jobs"], json!([]));

    let payload = json!({ "world": world.id, "bridge_key": "lepw_secret" });
    let job = jobs::add_for_agent(&pool, &world.id, "create_world", &payload)
        .await
        .unwrap();
    jobs::add(&pool, &world.id, "ping", &json!({}))
        .await
        .unwrap();

    // The agent gets its job, and only its job.
    let (_, json) = call(&state, Method::GET, JOBS, Some(&key), None).await;
    assert_eq!(json["jobs"].as_array().unwrap().len(), 1);
    assert_eq!(json["jobs"][0]["id"], job);
    assert_eq!(json["jobs"][0]["kind"], "create_world");
    assert_eq!(json["jobs"][0]["payload"]["bridge_key"], "lepw_secret");

    // A world gets neither the job nor a way to answer it.
    let world_jobs = "/api/world/v1/jobs";
    let (_, json) = call(&state, Method::GET, world_jobs, Some(&world_key), None).await;
    assert_eq!(json["jobs"].as_array().unwrap().len(), 1);
    assert_eq!(json["jobs"][0]["kind"], "ping");
    let result = json!({ "ok": true, "message": "" });
    let (status, _) = call(
        &state,
        Method::POST,
        &format!("{world_jobs}/{job}/result"),
        Some(&world_key),
        Some(result.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Nobody fetches or answers without the key of the agent.
    let (status, _) = call(&state, Method::GET, JOBS, Some(&world_key), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let path = format!("{JOBS}/{job}/result");
    let (status, _) = call(&state, Method::POST, &path, None, Some(result.clone())).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let answer = Some(result.clone());
    let (status, _) = call(&state, Method::POST, &path, Some(&key), answer).await;
    assert_eq!(status, StatusCode::OK);
    let (_, json) = call(&state, Method::GET, JOBS, Some(&key), None).await;
    assert_eq!(json["jobs"], json!([]));
    let done = jobs::state(&pool, &job).await.unwrap().unwrap();
    assert_eq!(done.ok, Some(true));

    let unknown = format!("{JOBS}/no-such-job/result");
    let (status, _) = call(&state, Method::POST, &unknown, Some(&key), Some(result)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_waiting_request_returns_when_a_job_comes_in() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let (world, _) = worlds::add(&pool, "7b").await.unwrap();
    let state = AppState::new(pool.clone());

    let waiting = {
        let state = state.clone();
        let key = key.clone();
        tokio::spawn(async move {
            let path = "/api/agent/v1/jobs?wait=20";
            call(&state, Method::GET, path, Some(&key), None).await
        })
    };
    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    jobs::add_for_agent(&pool, &world.id, "create_world", &json!({}))
        .await
        .unwrap();
    state.waiters.wake(jobs::AGENT_BELL);
    let (status, json) = tokio::time::timeout(std::time::Duration::from_secs(5), waiting)
        .await
        .expect("the request kept waiting")
        .unwrap();
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["jobs"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn the_backend_mirrors_the_worlds_the_agent_reports() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let (world, _) = worlds::add(&pool, "7b").await.unwrap();
    let state = AppState::new(pool.clone());

    let report = json!({
        "version": "0.1.0",
        "free_disk_bytes": 1,
        "template": "bdbbf00c8a29",
        "worlds": [
            { "id": world.id, "port": 30004, "template": "BDBBF00C8A29", "running": true },
            { "id": "made-up", "port": 30005, "template": "bdbbf00c8a29" },
        ],
    });
    let (status, _) = call(&state, Method::POST, REPORT, Some(&key), Some(report)).await;
    assert_eq!(status, StatusCode::OK);
    let all = worlds::list(&pool).await.unwrap();
    // The agent cannot make a world up by naming it.
    assert_eq!(all.len(), 1);
    assert_eq!(all[0].port, Some(30004));
    assert_eq!(all[0].template_version.as_deref(), Some("bdbbf00c8a29"));
    assert_eq!(all[0].running, Some(true));

    for worlds in [
        json!([{ "id": world.id, "port": 0, "template": "bdbbf00c8a29" }]),
        json!([{ "id": world.id, "port": 30004, "template": "../x" }]),
        json!([{ "id": world.id, "port": 70000, "template": "bdbbf00c8a29" }]),
    ] {
        let report = json!({ "version": "0.1.0", "free_disk_bytes": 1, "worlds": worlds });
        let (status, _) = call(&state, Method::POST, REPORT, Some(&key), Some(report)).await;
        assert!(status.is_client_error(), "{status}");
    }
}

#[tokio::test]
async fn a_report_that_cannot_be_read_is_refused() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let state = AppState::new(pool.clone());

    for body in [
        json!({ "version": "", "free_disk_bytes": 1 }),
        json!({ "version": "x".repeat(41), "free_disk_bytes": 1 }),
        json!({ "version": "0.1\n0", "free_disk_bytes": 1 }),
        json!({ "version": "0.1.0", "free_disk_bytes": 1, "template": "" }),
        json!({ "version": "0.1.0", "free_disk_bytes": 1, "template": "../x" }),
        json!({ "version": "0.1.0", "free_disk_bytes": 1, "template": "a".repeat(65) }),
    ] {
        let (status, json) = call(&state, Method::POST, REPORT, Some(&key), Some(body)).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(json["code"], "invalid_request");
    }
    let (status, _) = call(
        &state,
        Method::POST,
        REPORT,
        Some(&key),
        Some(json!({ "version": "0.1.0", "free_disk_bytes": -5 })),
    )
    .await;
    assert!(status.is_client_error());
    let server = game_server::describe(&pool).await.unwrap().unwrap();
    assert_eq!(server.last_seen_at, None);
}
