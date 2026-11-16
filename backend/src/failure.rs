//! Answers for requests that failed. Every failure carries a fixed code,
//! which the frontend translates, and an English sentence for logs.

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use lep_protocol::{ApiError, ErrorCode};

#[derive(Debug)]
pub struct Failure {
    pub status: StatusCode,
    pub code: ErrorCode,
    pub message: String,
}

impl Failure {
    pub fn new(status: StatusCode, code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
        }
    }

    pub fn unauthorized(message: impl Into<String>) -> Self {
        Self::new(StatusCode::UNAUTHORIZED, ErrorCode::Unauthorized, message)
    }

    pub fn not_found(message: impl Into<String>) -> Self {
        Self::new(StatusCode::NOT_FOUND, ErrorCode::NotFound, message)
    }

    pub fn invalid_request(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, ErrorCode::InvalidRequest, message)
    }

    pub fn too_large(message: impl Into<String>) -> Self {
        Self::new(StatusCode::PAYLOAD_TOO_LARGE, ErrorCode::TooLarge, message)
    }
}

impl IntoResponse for Failure {
    fn into_response(self) -> Response {
        let body = ApiError {
            code: self.code,
            message: self.message,
        };
        (self.status, Json(body)).into_response()
    }
}

impl From<anyhow::Error> for Failure {
    fn from(err: anyhow::Error) -> Self {
        // The details belong into the log, not to the caller.
        tracing::error!("request failed: {err:#}");
        Self::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            ErrorCode::Internal,
            "the backend could not do this",
        )
    }
}
