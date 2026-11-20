//! The interface for the agent, called without a network.

use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::{db, game_server, worlds};
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
async fn a_report_that_cannot_be_read_is_refused() {
    let pool = db::open_in_memory().await.unwrap();
    let key = game_server::rekey(&pool).await.unwrap();
    let state = AppState::new(pool.clone());

    for body in [
        json!({ "version": "", "free_disk_bytes": 1 }),
        json!({ "version": "x".repeat(41), "free_disk_bytes": 1 }),
        json!({ "version": "0.1\n0", "free_disk_bytes": 1 }),
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
