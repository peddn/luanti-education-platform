//! The interface for the worlds, called without a network.

use std::time::Duration;

use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use axum::Router;
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::{db, jobs, worlds};
use serde_json::{json, Value};
use tower::ServiceExt;

struct Setup {
    state: AppState,
    world_id: String,
    key: String,
}

impl Setup {
    async fn new() -> Self {
        let pool = db::open_in_memory().await.unwrap();
        let (world, key) = worlds::add(&pool, "7b").await.unwrap();
        Self {
            state: AppState::new(pool),
            world_id: world.id,
            key,
        }
    }

    fn router(&self) -> Router {
        app::router(self.state.clone())
    }

    async fn call(
        &self,
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
        let response = self
            .router()
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

    async fn post(&self, path: &str, body: Value) -> (StatusCode, Value) {
        self.call(Method::POST, path, Some(&self.key), Some(body))
            .await
    }

    async fn get(&self, path: &str) -> (StatusCode, Value) {
        self.call(Method::GET, path, Some(&self.key), None).await
    }
}

fn started(id: &str) -> Value {
    json!({
        "id": id,
        "kind": "world_started",
        "time": 1700000000,
        "payload": { "engine": "5.18.0", "mods": ["lep_core", "lep_bridge"] }
    })
}

#[tokio::test]
async fn requests_without_a_valid_key_are_turned_away() {
    let setup = Setup::new().await;
    let body = json!({ "events": [] });

    for key in [None, Some("lepw_wrong"), Some("")] {
        let (status, json) = setup
            .call(
                Method::POST,
                "/api/world/v1/events",
                key,
                Some(body.clone()),
            )
            .await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
        assert_eq!(json["code"], "unauthorized");
        assert!(json["message"].is_string());

        let (status, _) = setup
            .call(Method::GET, "/api/world/v1/jobs", key, None)
            .await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }
}

#[tokio::test]
async fn events_are_taken_in_once() {
    let setup = Setup::new().await;
    let batch = json!({ "events": [started("e1"), started("e2")] });

    let (status, json) = setup.post("/api/world/v1/events", batch.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        json["results"],
        json!([
            { "id": "e1", "outcome": "accepted" },
            { "id": "e2", "outcome": "accepted" }
        ])
    );

    // The answer got lost and the world sends the batch again.
    let (_, json) = setup.post("/api/world/v1/events", batch).await;
    assert_eq!(json["results"][0]["outcome"], "duplicate");
    assert_eq!(json["results"][1]["outcome"], "duplicate");

    let world = worlds::find_by_name(&setup.state.db, "7b")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(world.engine.as_deref(), Some("5.18.0"));
    assert!(world.last_seen_at.is_some());
}

#[tokio::test]
async fn events_the_backend_cannot_use_do_not_block_the_others() {
    let setup = Setup::new().await;
    let batch = json!({ "events": [
        { "id": "e1", "kind": "from_the_future", "time": 1, "payload": {} },
        { "id": "e2", "kind": "world_started", "time": 1, "payload": { "engine": 5 } },
        started("e3")
    ] });
    let (status, json) = setup.post("/api/world/v1/events", batch).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["results"][0]["outcome"], "unknown");
    assert_eq!(json["results"][1]["outcome"], "invalid");
    assert_eq!(json["results"][2]["outcome"], "accepted");
}

#[tokio::test]
async fn a_batch_that_is_too_large_or_no_batch_is_refused() {
    let setup = Setup::new().await;
    let events: Vec<Value> = (0..101).map(|n| started(&format!("e{n}"))).collect();
    let (status, _) = setup
        .post("/api/world/v1/events", json!({ "events": events }))
        .await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);

    let (status, _) = setup
        .post("/api/world/v1/events", json!({ "something": 1 }))
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn jobs_are_fetched_and_their_result_is_noted() {
    let setup = Setup::new().await;
    let (status, json) = setup.get("/api/world/v1/jobs").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["jobs"], json!([]));

    let job = jobs::add(&setup.state.db, &setup.world_id, "ping", &json!({}))
        .await
        .unwrap();
    let (_, json) = setup.get("/api/world/v1/jobs").await;
    assert_eq!(
        json["jobs"],
        json!([{ "id": job, "kind": "ping", "payload": {} }])
    );

    let path = format!("/api/world/v1/jobs/{job}/result");
    let (status, _) = setup
        .post(&path, json!({ "ok": true, "message": "pong" }))
        .await;
    assert_eq!(status, StatusCode::OK);

    let (_, json) = setup.get("/api/world/v1/jobs").await;
    assert_eq!(json["jobs"], json!([]));
    let state = jobs::state(&setup.state.db, &job).await.unwrap().unwrap();
    assert_eq!(state.ok, Some(true));
    assert_eq!(state.message.as_deref(), Some("pong"));
}

#[tokio::test]
async fn a_result_needs_a_job_of_this_world() {
    let setup = Setup::new().await;
    let (status, _) = setup
        .post(
            "/api/world/v1/jobs/no-such-job/result",
            json!({ "ok": true }),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (other, other_key) = worlds::add(&setup.state.db, "8a").await.unwrap();
    let job = jobs::add(&setup.state.db, &other.id, "ping", &json!({}))
        .await
        .unwrap();
    let path = format!("/api/world/v1/jobs/{job}/result");
    let (status, _) = setup.post(&path, json!({ "ok": true })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = setup
        .call(
            Method::POST,
            &path,
            Some(&other_key),
            Some(json!({ "ok": true })),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn waiting_for_jobs_ends_empty_after_the_time() {
    let setup = Setup::new().await;
    let started = std::time::Instant::now();
    let (status, json) = setup.get("/api/world/v1/jobs?wait=1").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["jobs"], json!([]));
    assert!(started.elapsed() >= Duration::from_millis(900));
    assert!(started.elapsed() < Duration::from_secs(5));
}

#[tokio::test]
async fn a_waiting_world_is_woken_by_a_new_job() {
    let setup = Setup::new().await;
    let state = setup.state.clone();
    let world_id = setup.world_id.clone();

    let waiting = tokio::spawn(async move { setup.get("/api/world/v1/jobs?wait=20").await });
    tokio::time::sleep(Duration::from_millis(100)).await;

    let job = jobs::add(&state.db, &world_id, "ping", &json!({}))
        .await
        .unwrap();
    state.waiters.wake(&world_id);

    let (status, json) = tokio::time::timeout(Duration::from_secs(3), waiting)
        .await
        .expect("the waiting request was not woken")
        .unwrap();
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["jobs"][0]["id"], job);
}
