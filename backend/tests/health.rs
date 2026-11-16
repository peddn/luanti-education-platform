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
    let (status, json) = get(app::router(AppState::new(pool)), "/api/health").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["status"], "ok");
    assert_eq!(json["database"], true);
    assert_eq!(json["version"], env!("CARGO_PKG_VERSION"));
}

#[tokio::test]
async fn health_reports_a_missing_database() {
    let pool = db::open_in_memory().await.unwrap();
    pool.close().await;
    let (status, json) = get(app::router(AppState::new(pool)), "/api/health").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["status"], "degraded");
    assert_eq!(json["database"], false);
}

#[tokio::test]
async fn openapi_describes_the_health_check() {
    let pool = db::open_in_memory().await.unwrap();
    let (status, json) = get(app::router(AppState::new(pool)), "/api/openapi.json").await;

    assert_eq!(status, StatusCode::OK);
    assert!(json["paths"]["/api/health"]["get"].is_object());
    assert!(json["components"]["schemas"]["Health"].is_object());
    assert!(json["components"]["schemas"]["HealthStatus"].is_object());
}

#[tokio::test]
async fn unknown_paths_are_not_found() {
    let pool = db::open_in_memory().await.unwrap();
    let router = app::router(AppState::new(pool));
    let (status, json) = get(router.clone(), "/api/nothing").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(json["code"], "not_found");
    let (status, _) = get(router, "/somewhere").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

async fn get_text(router: axum::Router, path: &str) -> (StatusCode, String) {
    let response = router
        .oneshot(Request::get(path).body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, String::from_utf8_lossy(&bytes).into_owned())
}

#[tokio::test]
async fn serves_the_built_frontend_next_to_the_interface() {
    let folder = tempfile::tempdir().unwrap();
    std::fs::write(folder.path().join("index.html"), "<html>LEP</html>").unwrap();
    std::fs::create_dir(folder.path().join("assets")).unwrap();
    std::fs::write(folder.path().join("assets/app.js"), "console.log(1)").unwrap();
    assert!(app::has_frontend(folder.path()));

    let pool = db::open_in_memory().await.unwrap();
    let router = app::router_with_frontend(AppState::new(pool), folder.path());

    let (status, body) = get_text(router.clone(), "/").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("LEP"));

    let (status, body) = get_text(router.clone(), "/assets/app.js").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("console.log"));

    // A page of the frontend, which only the frontend knows.
    let (status, body) = get_text(router.clone(), "/groups/7b").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("LEP"));

    // The interface stays what it is.
    let (status, json) = get(router.clone(), "/api/health").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["status"], "ok");
    let (status, json) = get(router, "/api/nothing").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(json["code"], "not_found");
}

#[tokio::test]
async fn a_folder_without_index_is_no_frontend() {
    let folder = tempfile::tempdir().unwrap();
    assert!(!app::has_frontend(folder.path()));
    assert!(!app::has_frontend(&folder.path().join("missing")));
}
