//! The routes of the skeleton, called without a network.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::db;
use serde_json::Value;
use tower::ServiceExt;

async fn get(router: axum::Router, path: &str) -> (StatusCode, Value) {
    let response = router
        .oneshot(Request::get(path).body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, json)
}

#[tokio::test]
async fn health_reports_ok() {
    let pool = db::open_in_memory().await.unwrap();
    let (status, json) = get(app::router(AppState { db: pool }), "/api/health").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["status"], "ok");
    assert_eq!(json["database"], true);
    assert_eq!(json["version"], env!("CARGO_PKG_VERSION"));
}

#[tokio::test]
async fn health_reports_a_missing_database() {
    let pool = db::open_in_memory().await.unwrap();
    pool.close().await;
    let (status, json) = get(app::router(AppState { db: pool }), "/api/health").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["status"], "degraded");
    assert_eq!(json["database"], false);
}

#[tokio::test]
async fn openapi_describes_the_health_check() {
    let pool = db::open_in_memory().await.unwrap();
    let (status, json) = get(app::router(AppState { db: pool }), "/api/openapi.json").await;

    assert_eq!(status, StatusCode::OK);
    assert!(json["paths"]["/api/health"]["get"].is_object());
    assert!(json["components"]["schemas"]["Health"].is_object());
    assert!(json["components"]["schemas"]["HealthStatus"].is_object());
}

#[tokio::test]
async fn unknown_paths_are_not_found() {
    let pool = db::open_in_memory().await.unwrap();
    let (status, _) = get(app::router(AppState { db: pool }), "/api/nothing").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
