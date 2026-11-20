//! Interface for the agent on the game server. It calls with its own
//! key, which opens nothing else.

use axum::extract::{FromRequestParts, Path, Query, State};
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use axum::routing::{get, post};
use axum::{Json, Router};
use lep_protocol::agent::{AgentReport, WorldState};
use lep_protocol::web::ChangeTopic;
use lep_protocol::world::{Done, JobList, JobResult};
use lep_protocol::ApiError;

use crate::app::AppState;
use crate::failure::Failure;
use crate::jobs::{self, AGENT_BELL};
use crate::world_api::{wait_duration, JobsQuery};
use crate::{game_server, worlds};

/// Longest version text an agent may send.
const MAX_VERSION_LENGTH: usize = 40;
/// Longest version of a template an agent may send: a whole checksum.
const MAX_TEMPLATE_LENGTH: usize = 64;
/// Most worlds one report may name.
const MAX_WORLDS: usize = 1000;

/// Returns true if a text can be the version of a template.
fn is_template_version(text: &str) -> bool {
    !text.is_empty()
        && text.len() <= MAX_TEMPLATE_LENGTH
        && text.chars().all(|c| c.is_ascii_hexdigit())
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/v1/report", post(report))
        .route("/v1/jobs", get(fetch_jobs))
        .route("/v1/jobs/{id}/result", post(report_result))
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
    let template = report.template.as_deref().map(str::trim);
    if template.is_some_and(|template| !is_template_version(template)) {
        return Err(Failure::invalid_request(
            "the version of the template cannot be read",
        ));
    }
    if report.worlds.len() > MAX_WORLDS
        || report
            .worlds
            .iter()
            .any(|world| world.port == 0 || !is_template_version(&world.template))
    {
        return Err(Failure::invalid_request("the worlds cannot be read"));
    }
    let worlds: Vec<WorldState> = report
        .worlds
        .iter()
        .map(|world| WorldState {
            id: world.id.clone(),
            port: world.port,
            template: world.template.to_ascii_lowercase(),
            running: world.running,
        })
        .collect();
    let report = AgentReport {
        version: version.to_owned(),
        free_disk_bytes: report.free_disk_bytes,
        template: template.map(str::to_ascii_lowercase),
        worlds,
    };
    game_server::note_report(&state.db, &report).await?;
    // Only worlds the backend knows are touched: the agent cannot make
    // one up by naming it.
    for world_id in worlds::note_agent_state(&state.db, &report.worlds).await? {
        state.changes.tell(&world_id, &[ChangeTopic::Group]);
    }
    Ok(Json(Done {}))
}

/// Returns the jobs that wait for the agent. If there are none, the
/// request stays open for up to `wait` seconds and returns as soon as
/// one comes.
#[utoipa::path(
    get,
    path = "/api/agent/v1/jobs",
    params(("wait" = Option<u64>, Query, description = "Seconds to wait, at most 25")),
    responses(
        (status = 200, description = "The waiting jobs, possibly none", body = JobList),
        (status = 401, description = "Missing or wrong key", body = ApiError),
    ),
    security(("agent_key" = []))
)]
pub async fn fetch_jobs(
    State(state): State<AppState>,
    _agent: CallingAgent,
    Query(query): Query<JobsQuery>,
) -> Result<Json<JobList>, Failure> {
    let wait = wait_duration(query.wait);

    // Listen before looking, so a job that comes in between is not missed.
    let bell = state.waiters.of(AGENT_BELL);
    let rung = bell.notified();
    tokio::pin!(rung);
    rung.as_mut().enable();

    let waiting = jobs::take_waiting_for_agent(&state.db).await?;
    if !waiting.is_empty() || wait.is_zero() {
        return Ok(Json(JobList { jobs: waiting }));
    }
    // Woken or not, look again: jobs can also be put in by another
    // process, which rings no bell here.
    tokio::select! {
        _ = tokio::time::timeout(wait, rung) => {}
        () = state.changes.stopped() => {}
    }
    let waiting = jobs::take_waiting_for_agent(&state.db).await?;
    Ok(Json(JobList { jobs: waiting }))
}

/// Notes how a job for the agent went.
#[utoipa::path(
    post,
    path = "/api/agent/v1/jobs/{id}/result",
    params(("id" = String, Path, description = "Id of the job")),
    request_body = JobResult,
    responses(
        (status = 200, description = "Noted", body = Done),
        (status = 401, description = "Missing or wrong key", body = ApiError),
        (status = 404, description = "The agent has no such job", body = ApiError),
    ),
    security(("agent_key" = []))
)]
pub async fn report_result(
    State(state): State<AppState>,
    _agent: CallingAgent,
    Path(job_id): Path<String>,
    Json(result): Json<JobResult>,
) -> Result<Json<Done>, Failure> {
    let Some(world_id) = jobs::finish_for_agent(&state.db, &job_id, &result).await? else {
        return Err(Failure::not_found("no such job"));
    };
    state.changes.tell(&world_id, &[ChangeTopic::Group]);
    Ok(Json(Done {}))
}
