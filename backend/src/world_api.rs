//! The interface for the worlds, under `/api/world/v1`.
//!
//! Every request carries the key of the world in the header
//! `Authorization: Bearer <key>`. The world always calls; the backend
//! never reaches out to a world.

use std::time::Duration;

use axum::extract::{FromRequestParts, Path, Query, State};
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use axum::routing::{get, post};
use axum::{Json, Router};
use lep_protocol::world::{
    Done, EventBatch, EventBatchResult, EventResult, JobList, JobResult, MAX_BATCH,
    MAX_WAIT_SECONDS,
};
use lep_protocol::ApiError;
use serde::Deserialize;

use crate::app::AppState;
use crate::failure::Failure;
use crate::worlds::World;
use crate::{events, jobs, worlds};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/v1/events", post(send_events))
        .route("/v1/jobs", get(fetch_jobs))
        .route("/v1/jobs/{id}/result", post(report_result))
}

/// The world a request comes from, found by its key.
pub struct CallingWorld(pub World);

impl FromRequestParts<AppState> for CallingWorld {
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
        let world = worlds::find_by_key(&state.db, key)
            .await?
            .ok_or_else(denied)?;
        Ok(Self(world))
    }
}

/// Takes in events of a world. Every event is handled once, however often
/// it is sent.
#[utoipa::path(
    post,
    path = "/api/world/v1/events",
    request_body = EventBatch,
    responses(
        (status = 200, description = "One result per event", body = EventBatchResult),
        (status = 401, description = "Missing or wrong key", body = ApiError),
        (status = 413, description = "Too many events in one request", body = ApiError),
    ),
    security(("world_key" = []))
)]
pub async fn send_events(
    State(state): State<AppState>,
    CallingWorld(world): CallingWorld,
    Json(batch): Json<EventBatch>,
) -> Result<Json<EventBatchResult>, Failure> {
    if batch.events.len() > MAX_BATCH {
        return Err(Failure::too_large(format!(
            "at most {MAX_BATCH} events per request"
        )));
    }
    let mut results = Vec::with_capacity(batch.events.len());
    for event in &batch.events {
        let outcome = events::take_in(&state, &world.id, event).await?;
        results.push(EventResult {
            id: event.id.clone(),
            outcome,
        });
    }
    Ok(Json(EventBatchResult { results }))
}

#[derive(Debug, Deserialize)]
pub struct JobsQuery {
    /// Seconds to wait for a job if none is there.
    wait: Option<u64>,
}

/// Returns the jobs that wait for a world. If there are none, the request
/// stays open for up to `wait` seconds and returns as soon as one comes.
#[utoipa::path(
    get,
    path = "/api/world/v1/jobs",
    params(("wait" = Option<u64>, Query, description = "Seconds to wait, at most 25")),
    responses(
        (status = 200, description = "The waiting jobs, possibly none", body = JobList),
        (status = 401, description = "Missing or wrong key", body = ApiError),
    ),
    security(("world_key" = []))
)]
pub async fn fetch_jobs(
    State(state): State<AppState>,
    CallingWorld(world): CallingWorld,
    Query(query): Query<JobsQuery>,
) -> Result<Json<JobList>, Failure> {
    let wait = wait_duration(query.wait);

    // Listen before looking, so a job that comes in between is not missed.
    let bell = state.waiters.of(&world.id);
    let rung = bell.notified();
    tokio::pin!(rung);
    rung.as_mut().enable();

    let waiting = jobs::take_waiting(&state.db, &world.id).await?;
    if !waiting.is_empty() || wait.is_zero() {
        return Ok(Json(JobList { jobs: waiting }));
    }
    // Woken or not, look again: jobs can also be put in by another
    // process, which rings no bell here.
    let _ = tokio::time::timeout(wait, rung).await;
    let waiting = jobs::take_waiting(&state.db, &world.id).await?;
    Ok(Json(JobList { jobs: waiting }))
}

/// Returns how long a request for jobs stays open: what the world asks
/// for, but never longer than the limit.
fn wait_duration(asked: Option<u64>) -> Duration {
    Duration::from_secs(asked.unwrap_or(0).min(MAX_WAIT_SECONDS))
}

/// Notes how a job went.
#[utoipa::path(
    post,
    path = "/api/world/v1/jobs/{id}/result",
    params(("id" = String, Path, description = "Id of the job")),
    request_body = JobResult,
    responses(
        (status = 200, description = "Noted", body = Done),
        (status = 401, description = "Missing or wrong key", body = ApiError),
        (status = 404, description = "The world has no such job", body = ApiError),
    ),
    security(("world_key" = []))
)]
pub async fn report_result(
    State(state): State<AppState>,
    CallingWorld(world): CallingWorld,
    Path(job_id): Path<String>,
    Json(result): Json<JobResult>,
) -> Result<Json<Done>, Failure> {
    if !jobs::finish(&state.db, &world.id, &job_id, &result).await? {
        return Err(Failure::not_found("no such job"));
    }
    Ok(Json(Done {}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn waiting_is_capped() {
        assert_eq!(wait_duration(None), Duration::ZERO);
        assert_eq!(wait_duration(Some(5)), Duration::from_secs(5));
        assert_eq!(
            wait_duration(Some(100_000)),
            Duration::from_secs(MAX_WAIT_SECONDS)
        );
    }
}
