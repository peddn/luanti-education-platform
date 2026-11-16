//! The interface for the browser, under `/api/web/v1`.
//!
//! A teacher logs in with a link from a mail and is known by a session
//! cookie from then on. Confirming an address and asking for a login link
//! need no session: there the token from the mail is the proof.

use axum::extract::rejection::JsonRejection;
use axum::extract::{FromRequestParts, State};
use axum::http::header::{COOKIE, SET_COOKIE};
use axum::http::request::Parts;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{AppendHeaders, IntoResponse};
use axum::routing::{get, post};
use axum::{Json, Router};
use lep_protocol::web::{ConfirmRequest, Confirmed, LoginLinkRequest, LoginRequest, Me};
use lep_protocol::world::Done;
use lep_protocol::{ApiError, ErrorCode};

use crate::app::AppState;
use crate::failure::Failure;
use crate::logins::{self, LoggedIn, SESSION_SECONDS};
use crate::teachers::{self, ConfirmError};
use crate::{clock, mail, web_access};

/// Name of the cookie that holds the session.
pub const SESSION_COOKIE: &str = "lep_session";

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/v1/confirm", post(confirm))
        .route("/v1/login/link", post(request_login_link))
        .route("/v1/login", post(log_in))
        .route("/v1/logout", post(log_out))
        .route("/v1/me", get(me))
}

/// Reads a JSON body, with our own answer if it cannot be read.
fn body<T>(body: Result<Json<T>, JsonRejection>) -> Result<T, Failure> {
    body.map(|Json(value)| value)
        .map_err(|_| Failure::invalid_request("the request cannot be read"))
}

/// Returns the session token from the cookies of a request.
fn session_token(headers: &HeaderMap) -> Option<&str> {
    headers
        .get_all(COOKIE)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(';'))
        .filter_map(|pair| pair.trim().split_once('='))
        .find(|(name, _)| *name == SESSION_COOKIE)
        .map(|(_, value)| value.trim())
        .filter(|value| !value.is_empty())
}

/// Builds the cookie that holds a session, or with `None` the one that
/// removes it. Scripts of the page cannot read it, and the browser sends
/// it only with requests that come from the web application itself.
fn session_cookie(state: &AppState, token: Option<&str>) -> String {
    let (value, max_age) = match token {
        Some(token) => (token, SESSION_SECONDS),
        None => ("", 0),
    };
    let secure = if state.public_url.starts_with("https://") {
        "; Secure"
    } else {
        ""
    };
    format!(
        "{SESSION_COOKIE}={value}; Path=/api/web; Max-Age={max_age}; HttpOnly; SameSite=Strict{secure}"
    )
}

/// The teacher a request comes from, found by the session cookie. The
/// privilege is checked with every request.
pub struct Teacher(pub LoggedIn);

impl FromRequestParts<AppState> for Teacher {
    type Rejection = Failure;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Failure> {
        let denied = || Failure::unauthorized("not logged in");
        let token = session_token(&parts.headers).ok_or_else(denied)?;
        let logged_in = logins::find_session(&state.db, token, clock::now())
            .await?
            .ok_or_else(denied)?;
        Ok(Self(logged_in))
    }
}

async fn describe(state: &AppState, logged_in: LoggedIn) -> Result<Me, Failure> {
    let worlds = teachers::world_names_of(&state.db, &logged_in.account).await?;
    Ok(Me {
        account: logged_in.account,
        email: logged_in.email,
        worlds,
        expires_at: logged_in.expires_at,
    })
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
    request: Result<Json<ConfirmRequest>, JsonRejection>,
) -> Result<Json<Confirmed>, Failure> {
    let request = body(request)?;
    match web_access::confirm(&state, request.token.trim()).await? {
        Ok(account) => Ok(Json(Confirmed { account })),
        Err(ConfirmError::InvalidToken) => Err(invalid_token()),
        Err(ConfirmError::AddressTaken) => Err(Failure::new(
            StatusCode::CONFLICT,
            ErrorCode::AddressTaken,
            "the address belongs to another account",
        )),
    }
}

fn invalid_token() -> Failure {
    Failure::new(
        StatusCode::BAD_REQUEST,
        ErrorCode::InvalidToken,
        "the token is unknown, used or too old",
    )
}

/// Sends a mail with a login link to an address, if a teacher may log in
/// with it. The answer is the same in every case, so nobody learns here
/// which addresses are known.
#[utoipa::path(
    post,
    path = "/api/web/v1/login/link",
    request_body = LoginLinkRequest,
    responses(
        (status = 200, description = "Taken note of, whether or not a mail goes out", body = Done),
        (status = 400, description = "The request cannot be read (invalid_request)", body = ApiError),
    )
)]
pub async fn request_login_link(
    State(state): State<AppState>,
    request: Result<Json<LoginLinkRequest>, JsonRejection>,
) -> Result<Json<Done>, Failure> {
    let request = body(request)?;
    if let Some(link) = logins::request_link(&state.db, &request.email, clock::now()).await? {
        let minutes = logins::LINK_SECONDS / 60;
        let mail = mail::login(
            &state.public_url,
            &link.to,
            &link.account,
            &link.token,
            minutes,
        );
        if let Err(err) = state.mailer.send(mail).await {
            tracing::error!("cannot send the login mail: {err:#}");
        }
    }
    Ok(Json(Done {}))
}

/// Logs a teacher in with the token from a login mail and sets the
/// session cookie. A token works once.
#[utoipa::path(
    post,
    path = "/api/web/v1/login",
    request_body = LoginRequest,
    responses(
        (status = 200, description = "Logged in, the session cookie is set", body = Me),
        (status = 400, description = "The token is unknown, used or too old (invalid_token), or the request cannot be read (invalid_request)", body = ApiError),
    )
)]
pub async fn log_in(
    State(state): State<AppState>,
    request: Result<Json<LoginRequest>, JsonRejection>,
) -> Result<impl IntoResponse, Failure> {
    let request = body(request)?;
    let now = clock::now();
    let started = logins::redeem(&state.db, request.token.trim(), now)
        .await?
        .ok_or_else(invalid_token)?;
    let logged_in = logins::find_session(&state.db, &started.token, now)
        .await?
        .ok_or_else(invalid_token)?;
    tracing::info!(account = %logged_in.account, "logged in");
    let cookie = session_cookie(&state, Some(&started.token));
    let me = describe(&state, logged_in).await?;
    Ok((AppendHeaders([(SET_COOKIE, cookie)]), Json(me)))
}

/// Ends the session of the request and removes the cookie. Without a
/// session nothing happens.
#[utoipa::path(
    post,
    path = "/api/web/v1/logout",
    responses((status = 200, description = "Logged out", body = Done))
)]
pub async fn log_out(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, Failure> {
    if let Some(token) = session_token(&headers) {
        logins::end_session(&state.db, token).await?;
    }
    let cookie = session_cookie(&state, None);
    Ok((AppendHeaders([(SET_COOKIE, cookie)]), Json(Done {})))
}

/// Says who is logged in.
#[utoipa::path(
    get,
    path = "/api/web/v1/me",
    responses(
        (status = 200, description = "The teacher of this session", body = Me),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn me(
    State(state): State<AppState>,
    Teacher(logged_in): Teacher,
) -> Result<Json<Me>, Failure> {
    Ok(Json(describe(&state, logged_in).await?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    fn cookies(values: &[&'static str]) -> HeaderMap {
        let mut headers = HeaderMap::new();
        for value in values {
            headers.append(COOKIE, HeaderValue::from_static(value));
        }
        headers
    }

    #[test]
    fn finds_the_session_among_the_cookies() {
        assert_eq!(
            session_token(&cookies(&["lep_session=leps_abc"])),
            Some("leps_abc")
        );
        assert_eq!(
            session_token(&cookies(&["theme=dark; lep_session=leps_abc; x=1"])),
            Some("leps_abc")
        );
        assert_eq!(
            session_token(&cookies(&["theme=dark", "lep_session=leps_abc"])),
            Some("leps_abc")
        );
        assert_eq!(session_token(&cookies(&[])), None);
        assert_eq!(session_token(&cookies(&["lep_session="])), None);
        assert_eq!(
            session_token(&cookies(&["other_lep_session=x; lep_sessions=y"])),
            None
        );
    }
}
