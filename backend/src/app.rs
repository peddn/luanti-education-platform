//! The web server: its routes and what they share.
//!
//! There are two separate interfaces. `/api/web` is for the browser of a
//! teacher and will need a login; it is empty so far. `/api/world` is for
//! the worlds, which call with their key.

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use lep_protocol::Health;
use sqlx::SqlitePool;
use utoipa::OpenApi;

use std::path::Path;

use tower_http::services::{ServeDir, ServeFile};

use crate::failure::Failure;
use crate::jobs::Waiters;
use crate::{db, world_api};

/// What every request handler can reach.
#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
    /// Wakes the worlds that wait for a job.
    pub waiters: Waiters,
}

impl AppState {
    pub fn new(db: SqlitePool) -> Self {
        Self {
            db,
            waiters: Waiters::default(),
        }
    }
}

/// Description of the interface, built from the types in `lep-protocol`.
#[derive(OpenApi)]
#[openapi(
    info(
        title = "Luanti Education Platform",
        description = "Interface of the LEP backend for the web frontend and the worlds."
    ),
    paths(
        health,
        world_api::send_events,
        world_api::fetch_jobs,
        world_api::report_result
    ),
    components(schemas(
        Health,
        lep_protocol::HealthStatus,
        lep_protocol::ApiError,
        lep_protocol::ErrorCode,
        lep_protocol::world::WorldStarted,
        lep_protocol::world::Modules,
        lep_protocol::world::Progress,
        lep_protocol::world::Trophies,
        lep_protocol::world::ProtocolEntry
    )),
    modifiers(&WorldKey)
)]
pub struct ApiDoc;

/// Tells the description how worlds prove who they are.
struct WorldKey;

impl utoipa::Modify for WorldKey {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        use utoipa::openapi::security::{Http, HttpAuthScheme, SecurityScheme};
        openapi
            .components
            .get_or_insert_with(Default::default)
            .add_security_scheme(
                "world_key",
                SecurityScheme::Http(Http::new(HttpAuthScheme::Bearer)),
            );
    }
}

/// Returns the description of the interface as the text that is checked
/// in as `api/openapi.json`.
pub fn openapi_json() -> String {
    let mut json = ApiDoc::openapi()
        .to_pretty_json()
        .expect("the description of the interface is not valid JSON");
    json.push('\n');
    json
}

/// Builds the router with all routes of the interface. Without a
/// frontend every other path is not found.
pub fn router(state: AppState) -> Router {
    Router::new().nest("/api", api(state))
}

/// Builds the router with the interface and the built frontend from a
/// folder. Paths the folder does not know get its `index.html`, because
/// the frontend has its own addresses for its pages.
pub fn router_with_frontend(state: AppState, folder: &Path) -> Router {
    let pages = ServeDir::new(folder).fallback(ServeFile::new(folder.join("index.html")));
    router(state).fallback_service(pages)
}

/// Returns true if a folder holds a built frontend.
pub fn has_frontend(folder: &Path) -> bool {
    folder.join("index.html").is_file()
}

fn api(state: AppState) -> Router {
    let web = Router::new();
    let world = world_api::router();

    Router::new()
        .route("/health", get(health))
        .route("/openapi.json", get(openapi))
        .nest("/web", web)
        .nest("/world", world)
        // An unknown path of the interface is an error, not a page.
        .fallback(|| async { Failure::not_found("no such path") })
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
