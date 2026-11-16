//! The interface for the browser, under `/api/web/v1`.
//!
//! So far it only confirms addresses, which needs no login: the token
//! from the mail is the proof.

use axum::extract::rejection::JsonRejection;
use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use lep_protocol::web::{ConfirmRequest, Confirmed};
use lep_protocol::{ApiError, ErrorCode};

use crate::app::AppState;
use crate::failure::Failure;
use crate::teachers::ConfirmError;
use crate::web_access;

pub fn router() -> Router<AppState> {
    Router::new().route("/v1/confirm", post(confirm))
}

/// Confirms the address a teacher entered at the desk, with the token
/// from the confirmation mail. A token works once.
#[utoipa::path(
    post,
    path = "/api/web/v1/confirm",
    request_body = ConfirmRequest,
    responses(
        (status = 200, description = "The address is confirmed", body = Confirmed),
        (status = 400, description = "The token is unknown, used or too old (invalid_token), or the request cannot be read (invalid_request)", body = ApiError),
        (status = 409, description = "The address belongs to another account (address_taken)", body = ApiError),
    )
)]
pub async fn confirm(
    State(state): State<AppState>,
    body: Result<Json<ConfirmRequest>, JsonRejection>,
) -> Result<Json<Confirmed>, Failure> {
    let Json(request) = body.map_err(|_| Failure::invalid_request("the request needs a token"))?;
    match web_access::confirm(&state, request.token.trim()).await? {
        Ok(account) => Ok(Json(Confirmed { account })),
        Err(ConfirmError::InvalidToken) => Err(Failure::new(
            StatusCode::BAD_REQUEST,
            ErrorCode::InvalidToken,
            "the token is unknown, used or too old",
        )),
        Err(ConfirmError::AddressTaken) => Err(Failure::new(
            StatusCode::CONFLICT,
            ErrorCode::AddressTaken,
            "the address belongs to another account",
        )),
    }
}
