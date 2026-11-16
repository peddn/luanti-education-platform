//! The web server: its routes and what they share.
//!
//! There are two separate interfaces. `/api/web` is for the browser of a
//! teacher and will need a login. `/api/world` is for the worlds, which
//! call with their key. Both are empty so far.

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use lep_protocol::Health;
use sqlx::SqlitePool;
use utoipa::OpenApi;

use crate::db;

/// What every request handler can reach.
#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
}

/// Description of the interface, built from the types in `lep-protocol`.
#[derive(OpenApi)]
#[openapi(
    info(
        title = "Luanti Education Platform",
        description = "Interface of the LEP backend for the web frontend and the worlds."
    ),
    paths(health),
    components(schemas(Health, lep_protocol::HealthStatus))
)]
pub struct ApiDoc;

/// Builds the router with all routes.
pub fn router(state: AppState) -> Router {
    let web = Router::new();
    let world = Router::new();

    Router::new()
        .route("/api/health", get(health))
        .route("/api/openapi.json", get(openapi))
        .nest("/api/web", web)
        .nest("/api/world", world)
        .with_state(state)
}

/// Says whether the backend can do its work.
#[utoipa::path(
    get,
    path = "/api/health",
    responses((status = 200, description = "State of the backend", body = Health))
)]
async fn health(State(state): State<AppState>) -> Json<Health> {
    let database = db::is_alive(&state.db).await;
    Json(Health::new(env!("CARGO_PKG_VERSION"), database))
}

/// Returns the OpenAPI description of the interface.
async fn openapi() -> Json<utoipa::openapi::OpenApi> {
    Json(ApiDoc::openapi())
}
