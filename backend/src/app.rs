//! The web server: its routes and what they share.
//!
//! There are two separate interfaces. `/api/web` is for the browser of a
//! teacher, who logs in with a link from a mail.
//! `/api/world` is for the worlds, which call with their key.

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use lep_protocol::Health;
use sqlx::SqlitePool;
use utoipa::OpenApi;

use std::path::Path;
use std::sync::Arc;

use tower_http::services::{ServeDir, ServeFile};

use crate::failure::Failure;
use crate::jobs::Waiters;
use crate::mail::Mailer;
use crate::{db, web_api, world_api};

/// What every request handler can reach.
#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
    /// Wakes the worlds that wait for a job.
    pub waiters: Waiters,
    /// The way mails leave the backend.
    pub mailer: Mailer,
    /// Address of the web application as browsers reach it, for links in
    /// mails.
    pub public_url: Arc<str>,
}

impl AppState {
    /// Builds the state with mails that go to the terminal and links
    /// for the test environment.
    pub fn new(db: SqlitePool) -> Self {
        Self::with(db, Mailer::Terminal, crate::config::DEFAULT_PUBLIC_URL)
    }

    pub fn with(db: SqlitePool, mailer: Mailer, public_url: &str) -> Self {
        Self {
            db,
            waiters: Waiters::default(),
            mailer,
            public_url: public_url.into(),
        }
    }
}

/// Description of the interface, built from the types in `lep-protocol`.
#[derive(OpenApi)]
#[openapi(
    info(
        title = "Luanti Education Platform",
        // The version of the interface, not of the program: this
        // description is open to everybody.
        version = "1",
        description = "Interface of the LEP backend for the web frontend and the worlds."
    ),
    paths(
        health,
        world_api::send_events,
        world_api::fetch_jobs,
        world_api::report_result,
        web_api::confirm,
        web_api::request_login_link,
        web_api::log_in,
        web_api::log_out,
        web_api::me,
        web_api::status
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
        lep_protocol::world::ProtocolEntry,
        lep_protocol::world::Teachers,
        lep_protocol::world::WebAccessRequest,
        lep_protocol::world::WebAccessAction,
        lep_protocol::world::WebAccessStatus,
        lep_protocol::web::ConfirmRequest,
        lep_protocol::web::Confirmed,
        lep_protocol::web::LoginLinkRequest,
        lep_protocol::web::LoginRequest,
        lep_protocol::web::Me,
        lep_protocol::web::Status,
        lep_protocol::web::MailTransport,
        lep_protocol::world::Done
    )),
    modifiers(&WorldKey)
)]
pub struct ApiDoc;

/// Tells the description how worlds and teachers prove who they are.
struct WorldKey;

impl utoipa::Modify for WorldKey {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        use utoipa::openapi::security::{
            ApiKey, ApiKeyValue, Http, HttpAuthScheme, SecurityScheme,
        };
        openapi
            .components
            .get_or_insert_with(Default::default)
            .add_security_scheme(
                "world_key",
                SecurityScheme::Http(Http::new(HttpAuthScheme::Bearer)),
            );
        openapi
            .components
            .get_or_insert_with(Default::default)
            .add_security_scheme(
                "session",
                SecurityScheme::ApiKey(ApiKey::Cookie(ApiKeyValue::new(
                    crate::web_api::SESSION_COOKIE,
                ))),
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
    let web = web_api::router();
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

/// Says whether the backend can do its work, and nothing else: everybody
/// may ask. The details are for teachers, under `/api/web/v1/status`.
#[utoipa::path(
    get,
    path = "/api/health",
    responses((status = 200, description = "State of the backend", body = Health))
)]
async fn health(State(state): State<AppState>) -> Json<Health> {
    let database = db::is_alive(&state.db).await;
    Json(Health::new(database))
}

/// Returns the OpenAPI description of the interface.
async fn openapi() -> Json<utoipa::openapi::OpenApi> {
    Json(ApiDoc::openapi())
}
