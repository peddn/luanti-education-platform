//! Interface for the agent on the game server. It calls with its own
//! key, which opens nothing else.

use axum::extract::{FromRequestParts, State};
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use axum::routing::post;
use axum::{Json, Router};
use lep_protocol::agent::AgentReport;
use lep_protocol::world::Done;
use lep_protocol::ApiError;

use crate::app::AppState;
use crate::failure::Failure;
use crate::game_server;

/// Longest version text an agent may send.
const MAX_VERSION_LENGTH: usize = 40;

pub fn router() -> Router<AppState> {
    Router::new().route("/v1/report", post(report))
}

/// Proof that a request comes from the agent.
pub struct CallingAgent;

impl FromRequestParts<AppState> for CallingAgent {
    type Rejection = Failure;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Failure> {
        let denied = || Failure::unauthorized("missing or wrong key");
        let key = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.strip_prefix("Bearer "))
            .map(str::trim)
            .filter(|key| !key.is_empty())
            .ok_or_else(denied)?;
        if game_server::is_key(&state.db, key).await? {
            Ok(Self)
        } else {
            Err(denied())
        }
    }
}

/// Takes in what the agent says about the game server.
#[utoipa::path(
    post,
    path = "/api/agent/v1/report",
    request_body = AgentReport,
    responses(
        (status = 200, description = "Noted", body = Done),
        (status = 400, description = "The report cannot be understood", body = ApiError),
        (status = 401, description = "Missing or wrong key", body = ApiError),
    ),
    security(("agent_key" = []))
)]
pub async fn report(
    State(state): State<AppState>,
    _agent: CallingAgent,
    Json(report): Json<AgentReport>,
) -> Result<Json<Done>, Failure> {
    let version = report.version.trim();
    if version.is_empty()
        || version.chars().count() > MAX_VERSION_LENGTH
        || version.chars().any(char::is_control)
    {
        return Err(Failure::invalid_request("the version cannot be read"));
    }
    let report = AgentReport {
        version: version.to_owned(),
        free_disk_bytes: report.free_disk_bytes,
    };
    game_server::note_report(&state.db, &report).await?;
    Ok(Json(Done {}))
}
