//! The interface for the browser, under `/api/web/v1`.
//!
//! A teacher logs in with a link from a mail and is known by a session
//! cookie from then on. Confirming an address and asking for a login link
//! need no session: there the token from the mail is the proof.

use axum::extract::rejection::JsonRejection;
use axum::extract::{FromRequestParts, Path, Query, Request, State};
use axum::http::header::{CACHE_CONTROL, CONTENT_DISPOSITION, CONTENT_TYPE, COOKIE, SET_COOKIE};
use axum::http::request::Parts;
use axum::http::{HeaderMap, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::sse::{Event as SseEvent, KeepAlive, Sse};
use axum::response::{AppendHeaders, IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use futures_util::stream::{self, Stream};
use lep_protocol::web::{
    AccessSlips, ChangeTopic, ConfirmRequest, Confirmed, DisplayLock, DisplayNameHistory,
    DraftRequest, Group, GroupChange, GroupProgress, Groups, LoginLinkRequest, LoginRequest,
    MailTransport, Me, NewGroup, ProgressChange, ProtocolPage, RemovalRequest, Removals,
    StaffCreate, StaffList, StartLevelChange, Status, Students, TeacherList, YearEnd,
    YearEndRequest, YEAR_END_CONFIRMATION,
};
use lep_protocol::world::Done;
use lep_protocol::{ApiError, ErrorCode, Health};

use std::collections::VecDeque;
use std::convert::Infallible;
use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

use tokio::sync::broadcast;

use crate::app::AppState;
use crate::changes;
use crate::display_names;
use crate::failure::Failure;
use crate::game_server;
use crate::groups::{self, ChangeError, CreateError, RefusedError};
use crate::jobs::AGENT_BELL;
use crate::logins::{self, LoggedIn, SESSION_SECONDS};
use crate::progress::{self, ChangeError as ChangeProgressError};
use crate::protocols;
use crate::removals::{self, OrderError};
use crate::staff::{self, StaffError};
use crate::students::{self, DraftError};
use crate::teachers::{self, ConfirmError};
use crate::year_end;
use crate::{clock, mail, web_access};
use lep_protocol::web::{GroupRewards, RewardsChange};
use serde::Deserialize;

/// Name of the cookie that holds the session.
pub const SESSION_COOKIE: &str = "lep_session";

pub fn router(state: &AppState) -> Router<AppState> {
    Router::new()
        .route("/v1/year-end", get(show_year_end).post(close_year))
        .route("/v1/groups/{id}/changes", get(watch_changes))
        .route("/v1/groups/{id}/protocols/{protocol}", get(show_protocol))
        .route(
            "/v1/groups/{id}/protocols/{protocol}/export",
            get(export_protocol),
        )
        .route("/v1/confirm", post(confirm))
        .route("/v1/login/link", post(request_login_link))
        .route("/v1/login", post(log_in))
        .route("/v1/logout", post(log_out))
        .route("/v1/me", get(me))
        .route("/v1/status", get(status))
        .route("/v1/groups", get(list_groups).post(create_group))
        .route(
            "/v1/groups/{id}",
            get(show_group).patch(change_group).delete(discard_group),
        )
        .route("/v1/groups/{id}/setup", post(retry_group))
        .route("/v1/teachers", get(list_teachers))
        .route(
            "/v1/groups/{id}/students",
            get(list_students).post(draft_students),
        )
        .route("/v1/groups/{id}/students/create", post(create_students))
        .route(
            "/v1/groups/{id}/students/{account}",
            axum::routing::delete(remove_student),
        )
        .route(
            "/v1/groups/{id}/students/{account}/reroll",
            post(reroll_student),
        )
        .route(
            "/v1/groups/{id}/students/{account}/password",
            post(reset_password),
        )
        .route(
            "/v1/groups/{id}/students/{account}/display-name",
            delete(remove_display_name),
        )
        .route(
            "/v1/groups/{id}/students/{account}/display-name/lock",
            post(lock_display_name),
        )
        .route(
            "/v1/groups/{id}/students/{account}/display-names",
            get(display_name_history),
        )
        .route(
            "/v1/groups/{id}/students/{account}/removal",
            post(order_removal).delete(take_back_removal),
        )
        .route("/v1/removals", get(list_removals))
        .route("/v1/staff", get(list_staff).post(create_staff))
        .route("/v1/staff/{account}/password", post(reset_staff_password))
        .route("/v1/staff/{account}/removal", post(remove_staff))
        .route(
            "/v1/groups/{id}/rewards",
            get(show_rewards).put(change_rewards),
        )
        .route("/v1/groups/{id}/progress", get(show_progress))
        .route("/v1/groups/{id}/progress/export", get(export_progress))
        .route(
            "/v1/groups/{id}/progress/start/{module}",
            post(change_start_level),
        )
        .route(
            "/v1/groups/{id}/progress/{account}/{module}",
            post(change_progress),
        )
        .layer(middleware::from_fn_with_state(state.clone(), tell_changes))
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
    let school_admin = groups::is_school_admin(&state.db, &logged_in.account).await?;
    Ok(Me {
        school_admin,
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
        state.mailer.send_later(mail, &link.account).await;
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

/// Says how the backend is doing, with the details that are nobody
/// else's business.
#[utoipa::path(
    get,
    path = "/api/web/v1/status",
    responses(
        (status = 200, description = "State of the backend", body = Status),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn status(
    State(state): State<AppState>,
    _teacher: Teacher,
) -> Result<Json<Status>, Failure> {
    // Who got this far was found in the database.
    Ok(Json(Status {
        status: Health::new(true).status,
        version: env!("CARGO_PKG_VERSION").to_owned(),
        mail: if state.mailer.is_smtp() {
            MailTransport::Smtp
        } else {
            MailTransport::Terminal
        },
        game_server: game_server::describe(&state.db).await?,
    }))
}

/// Lets only the school administration pass.
async fn school_admin_only(state: &AppState, account: &str) -> Result<(), Failure> {
    if groups::is_school_admin(&state.db, account).await? {
        Ok(())
    } else {
        Err(Failure::forbidden(
            "only the school administration may do this",
        ))
    }
}

/// Lists the groups of the teacher: all of them for the school
/// administration, else the ones the teacher is assigned to.
#[utoipa::path(
    get,
    path = "/api/web/v1/groups",
    responses(
        (status = 200, description = "The groups the teacher may see", body = Groups),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn list_groups(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
) -> Result<Json<Groups>, Failure> {
    let groups = groups::visible_to(&state.db, &teacher.account).await?;
    Ok(Json(Groups { groups }))
}

/// Shows one group. A group the teacher may not see does not exist for
/// them.
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "The group", body = Group),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group for this teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn show_group(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<Json<Group>, Failure> {
    groups::find_visible(&state.db, &teacher.account, &id)
        .await?
        .map(Json)
        .ok_or_else(|| Failure::not_found("no such group"))
}

/// Renames a group, sets its teachers or both. Only the school
/// administration may do this.
#[utoipa::path(
    patch,
    path = "/api/web/v1/groups/{id}",
    params(("id" = String, Path, description = "Identifier of the group")),
    request_body = GroupChange,
    responses(
        (status = 200, description = "The group as it is now", body = Group),
        (status = 400, description = "The name cannot be used or an account is not a teacher (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
        (status = 404, description = "No such group (not_found)", body = ApiError),
        (status = 409, description = "Another group has this name (name_taken)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn change_group(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
    request: Result<Json<GroupChange>, JsonRejection>,
) -> Result<Json<Group>, Failure> {
    school_admin_only(&state, &teacher.account).await?;
    let change = body(request)?;
    match groups::change(&state.db, &id, &change).await? {
        Ok(()) => {}
        Err(ChangeError::NotFound) => return Err(Failure::not_found("no such group")),
        Err(ChangeError::InvalidName) => {
            return Err(Failure::invalid_request(
                "a group name needs 1 to 60 characters",
            ))
        }
        Err(ChangeError::InvalidAddress) => {
            return Err(Failure::invalid_request(
                "the address is too long or cannot be printed",
            ))
        }
        Err(ChangeError::UnknownTeacher(account)) => {
            return Err(Failure::invalid_request(format!(
                "{account} is not a teacher"
            )))
        }
        Err(ChangeError::NameTaken) => {
            return Err(Failure::new(
                StatusCode::CONFLICT,
                ErrorCode::NameTaken,
                "another group has this name",
            ))
        }
    }
    tracing::info!(account = %teacher.account, group = %id, "group changed");
    groups::find_visible(&state.db, &teacher.account, &id)
        .await?
        .map(Json)
        .ok_or_else(|| Failure::not_found("no such group"))
}

/// Creates a group and asks the agent to set its world up. Only the
/// school administration may do this.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups",
    request_body = NewGroup,
    responses(
        (status = 200, description = "The new group, its world still pending", body = Group),
        (status = 400, description = "The name cannot be used (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
        (status = 409, description = "Another group has this name (name_taken), or there is no agent that could set the world up (no_game_server)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn create_group(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    request: Result<Json<NewGroup>, JsonRejection>,
) -> Result<Json<Group>, Failure> {
    school_admin_only(&state, &teacher.account).await?;
    let wanted = body(request)?;
    let id = match groups::create(&state.db, &wanted.name).await? {
        Ok(id) => id,
        Err(CreateError::InvalidName) => {
            return Err(Failure::invalid_request(
                "a group name needs 1 to 60 characters",
            ))
        }
        Err(CreateError::NameTaken) => {
            return Err(Failure::new(
                StatusCode::CONFLICT,
                ErrorCode::NameTaken,
                "another group has this name",
            ))
        }
        Err(CreateError::NoGameServer) => {
            return Err(Failure::new(
                StatusCode::CONFLICT,
                ErrorCode::NoGameServer,
                "there is no agent that could set the world up",
            ))
        }
    };
    // The agent hears of its job at once, not at its next request.
    state.waiters.wake(AGENT_BELL);
    tracing::info!(account = %teacher.account, group = %id, "group created");
    group_of(&state, &teacher.account, &id).await.map(Json)
}

/// Turns the reason a refused group could not be handled into an answer.
fn refused_failure(why: RefusedError) -> Failure {
    match why {
        RefusedError::NotFound => Failure::not_found("no such group"),
        RefusedError::NotRefused => Failure::new(
            StatusCode::CONFLICT,
            ErrorCode::WrongState,
            "this only works for a group whose world the agent refused",
        ),
    }
}

/// Asks the agent again to set up the world of a group it refused. Only
/// the school administration may do this.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/setup",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "The group, its world pending again", body = Group),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
        (status = 404, description = "No such group (not_found)", body = ApiError),
        (status = 409, description = "The agent did not refuse this group (wrong_state)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn retry_group(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<Json<Group>, Failure> {
    school_admin_only(&state, &teacher.account).await?;
    groups::retry(&state.db, &id)
        .await?
        .map_err(refused_failure)?;
    state.waiters.wake(AGENT_BELL);
    state.changes.tell(&id, &[ChangeTopic::Group]);
    tracing::info!(account = %teacher.account, group = %id, "setup of the group ordered again");
    group_of(&state, &teacher.account, &id).await.map(Json)
}

/// Removes a group whose world the agent refused. Such a world never
/// existed. Only the school administration may do this.
#[utoipa::path(
    delete,
    path = "/api/web/v1/groups/{id}",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "The group is gone", body = Done),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
        (status = 404, description = "No such group (not_found)", body = ApiError),
        (status = 409, description = "The agent did not refuse this group (wrong_state)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn discard_group(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<Json<Done>, Failure> {
    school_admin_only(&state, &teacher.account).await?;
    groups::discard(&state.db, &id)
        .await?
        .map_err(refused_failure)?;
    state.changes.tell(&id, &[ChangeTopic::Group]);
    tracing::info!(account = %teacher.account, group = %id, "refused group discarded");
    Ok(Json(Done {}))
}

/// Lists the accounts that can be assigned to groups. Only the school
/// administration may ask.
#[utoipa::path(
    get,
    path = "/api/web/v1/teachers",
    responses(
        (status = 200, description = "Everybody who holds the privilege for web access", body = TeacherList),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn list_teachers(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
) -> Result<Json<TeacherList>, Failure> {
    school_admin_only(&state, &teacher.account).await?;
    let teachers = groups::assignable(&state.db).await?;
    Ok(Json(TeacherList { teachers }))
}

/// Finds a group for a teacher who wants to work with its students: the
/// teachers of the group and the school administration may. For everybody
/// else the group does not exist.
async fn group_of(state: &AppState, account: &str, id: &str) -> Result<Group, Failure> {
    groups::find_visible(&state.db, account, id)
        .await?
        .ok_or_else(|| Failure::not_found("no such group"))
}

async fn students_of(state: &AppState, id: &str) -> Result<Json<Students>, Failure> {
    let students = students::list(&state.db, id).await?;
    Ok(Json(Students { students }))
}

fn draft_failure(error: DraftError) -> Failure {
    match error {
        DraftError::BadCount => Failure::invalid_request(format!(
            "between 1 and {} names can be rolled at once",
            students::MAX_DRAFT
        )),
        DraftError::GroupFull => Failure::invalid_request(format!(
            "a group has at most {} accounts",
            students::MAX_GROUP
        )),
        DraftError::NoNames => Failure::new(
            StatusCode::CONFLICT,
            ErrorCode::NoNames,
            "no free name turned up",
        ),
        DraftError::NotADraft => Failure::not_found("no such account that could still be changed"),
    }
}

/// Lists the accounts of the students of a group.
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}/students",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "The accounts, in the order they were rolled", body = Students),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group for this teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn list_students(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<Json<Students>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    students_of(&state, &id).await
}

/// Rolls names for new accounts. Nothing happens in the world yet: the
/// names are drafts that can be rolled again or removed.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/students",
    params(("id" = String, Path, description = "Identifier of the group")),
    request_body = DraftRequest,
    responses(
        (status = 200, description = "All accounts of the group", body = Students),
        (status = 400, description = "The count is not allowed or the group would get too large (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group for this teacher (not_found)", body = ApiError),
        (status = 409, description = "No free name turned up (no_names)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn draft_students(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
    request: Result<Json<DraftRequest>, JsonRejection>,
) -> Result<Json<Students>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    let request = body(request)?;
    students::draft(&state.db, &id, request.count)
        .await?
        .map_err(draft_failure)?;
    students_of(&state, &id).await
}

/// Replaces a name that is not an account yet by a newly rolled one.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/students/{account}/reroll",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "The name to replace"),
    ),
    responses(
        (status = 200, description = "All accounts of the group", body = Students),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or no such name that could still be changed (not_found)", body = ApiError),
        (status = 409, description = "No free name turned up (no_names)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn reroll_student(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account)): Path<(String, String)>,
) -> Result<Json<Students>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    students::reroll(&state.db, &id, &account)
        .await?
        .map_err(draft_failure)?;
    students_of(&state, &id).await
}

/// Removes a name that is not an account in the world.
#[utoipa::path(
    delete,
    path = "/api/web/v1/groups/{id}/students/{account}",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "The name to remove"),
    ),
    responses(
        (status = 200, description = "All accounts of the group", body = Students),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or no such name that could still be changed (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn remove_student(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account)): Path<(String, String)>,
) -> Result<Json<Students>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    students::remove(&state.db, &id, &account)
        .await?
        .map_err(draft_failure)?;
    students_of(&state, &id).await
}

/// Has the world create an account for every draft of the group and
/// returns the access slips with the start passwords. The passwords are
/// shown this once: the backend does not keep them.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/students/create",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "The access slips, shown once", body = AccessSlips),
        (status = 400, description = "There is no draft to create (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group for this teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn create_students(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<impl IntoResponse, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    let Some((_, slips)) = students::create(&state.db, &id).await? else {
        return Err(Failure::invalid_request(
            "there are no names to create accounts for",
        ));
    };
    state.waiters.wake(&id);
    tracing::info!(account = %teacher.account, group = %id, count = slips.len(), "accounts ordered");
    // Passwords must not stay in a cache of the browser or of a proxy.
    let no_store = AppendHeaders([(axum::http::header::CACHE_CONTROL, "no-store")]);
    Ok((no_store, Json(AccessSlips { slips })))
}

/// Makes up a new start password for the account of a student and asks
/// the world to set it. The password is shown this once. Until the world
/// has set it, the old one counts.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/students/{account}/password",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "The account that gets a new password"),
    ),
    responses(
        (status = 200, description = "One access slip, shown once", body = AccessSlips),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or no such account that exists in the world (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn reset_password(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account)): Path<(String, String)>,
) -> Result<impl IntoResponse, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    let Some(slip) = students::reset_password(&state.db, &id, &account).await? else {
        return Err(Failure::not_found(
            "no such account that exists in the world",
        ));
    };
    state.waiters.wake(&id);
    tracing::info!(account = %teacher.account, group = %id, student = %slip.account, "new password ordered");
    let no_store = AppendHeaders([(axum::http::header::CACHE_CONTROL, "no-store")]);
    Ok((no_store, Json(AccessSlips { slips: vec![slip] })))
}

/// Orders the world to take the display name of a student away. The
/// student may choose a new one right away, unless choosing is locked.
/// The answer shows the list with the order on its way.
#[utoipa::path(
    delete,
    path = "/api/web/v1/groups/{id}/students/{account}/display-name",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "Account name of the student"),
    ),
    responses(
        (status = 200, description = "The students of the group", body = Students),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or no such account that exists in the world (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn remove_display_name(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account)): Path<(String, String)>,
) -> Result<Json<Students>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    if !display_names::remove(&state.db, &id, &account, &teacher.account).await? {
        return Err(Failure::not_found(
            "no such account that exists in the world",
        ));
    }
    state.waiters.wake(&id);
    tracing::info!(account = %teacher.account, group = %id, student = %account, "removal of a display name ordered");
    Ok(Json(Students {
        students: students::list(&state.db, &id).await?,
    }))
}

/// Orders the world to delete the account of a student with everything
/// it knows about it. The backend deletes its copies when the world
/// reports that it did. A teacher of the group takes back an account
/// nobody ever logged in with; a used one only the school
/// administration deletes. It cannot be undone.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/students/{account}/removal",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "Account name of the student"),
    ),
    request_body = RemovalRequest,
    responses(
        (status = 200, description = "The students of the group, with the order on its way", body = Students),
        (status = 400, description = "The request does not carry the account name as confirmation (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "The account was used: only the school administration deletes it (forbidden)", body = ApiError),
        (status = 404, description = "No such group, or no such account that exists in the world (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn order_removal(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account)): Path<(String, String)>,
    wanted: Result<Json<RemovalRequest>, JsonRejection>,
) -> Result<Json<Students>, Failure> {
    let wanted = body(wanted)?;
    group_of(&state, &teacher.account, &id).await?;
    if wanted.confirm != account {
        return Err(Failure::invalid_request(
            "the request does not carry the account name as confirmation",
        ));
    }
    let school_admin = groups::is_school_admin(&state.db, &teacher.account).await?;
    match removals::order(&state.db, &id, &account, &teacher.account, school_admin).await? {
        Ok(()) => {}
        Err(OrderError::NotFound) => {
            return Err(Failure::not_found(
                "no such account that exists in the world",
            ))
        }
        Err(OrderError::Used) => {
            return Err(Failure::forbidden(
                "the account was used: only the school administration deletes it",
            ))
        }
    }
    state.waiters.wake(&id);
    tracing::warn!(account = %teacher.account, group = %id, student = %account, "deleting an account ordered");
    students_of(&state, &id).await
}

/// Takes back the order to delete an account, as long as the world has
/// not answered.
#[utoipa::path(
    delete,
    path = "/api/web/v1/groups/{id}/students/{account}/removal",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "Account name of the student"),
    ),
    responses(
        (status = 200, description = "The students of the group", body = Students),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or no order that waits for this account (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn take_back_removal(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account)): Path<(String, String)>,
) -> Result<Json<Students>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    if !removals::take_back(&state.db, &id, &account).await? {
        return Err(Failure::not_found("no order waits for this account"));
    }
    tracing::info!(account = %teacher.account, group = %id, student = %account, "order to delete an account taken back");
    students_of(&state, &id).await
}

/// Lists the accounts that were deleted on request: who, when, which
/// account, in which group. Nothing else is kept about them.
#[utoipa::path(
    get,
    path = "/api/web/v1/removals",
    responses(
        (status = 200, description = "The deleted accounts, newest first", body = Removals),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn list_removals(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
) -> Result<Json<Removals>, Failure> {
    school_admin_only(&state, &teacher.account).await?;
    Ok(Json(Removals {
        removals: removals::list(&state.db).await?,
    }))
}

fn staff_failure(error: StaffError) -> Failure {
    match error {
        StaffError::InvalidName => {
            Failure::invalid_request("a name has 2 to 19 characters: letters, digits, _ and -")
        }
        StaffError::Taken => Failure::new(
            StatusCode::CONFLICT,
            ErrorCode::AccountTaken,
            "this account name is taken or was deleted",
        ),
        StaffError::NoWorld => Failure::invalid_request("there is no world yet"),
        StaffError::NotFound => Failure::not_found("no such teacher"),
        StaffError::Protected => Failure::forbidden(
            "accounts of the school administration and the own account are not changed here",
        ),
    }
}

async fn staff_of(state: &AppState) -> Result<Json<StaffList>, Failure> {
    Ok(Json(StaffList {
        staff: staff::list(&state.db).await?,
    }))
}

/// Lists the accounts of all teachers, for the school administration.
#[utoipa::path(
    get,
    path = "/api/web/v1/staff",
    responses(
        (status = 200, description = "The accounts of the teachers", body = StaffList),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn list_staff(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
) -> Result<Json<StaffList>, Failure> {
    school_admin_only(&state, &teacher.account).await?;
    staff_of(&state).await
}

/// Has every world create the account of a teacher, with the privileges
/// of the bundle for teachers. The answer carries the slip with the
/// start password, once: it is stored nowhere.
#[utoipa::path(
    post,
    path = "/api/web/v1/staff",
    request_body = StaffCreate,
    responses(
        (status = 200, description = "The access slip of the new teacher", body = AccessSlips),
        (status = 400, description = "The name cannot be an account name, or there is no world (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
        (status = 409, description = "The name is taken or was deleted (account_taken)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn create_staff(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    wanted: Result<Json<StaffCreate>, JsonRejection>,
) -> Result<impl IntoResponse, Failure> {
    let wanted = body(wanted)?;
    school_admin_only(&state, &teacher.account).await?;
    let (slip, worlds) = staff::create(&state.db, &wanted.name, &teacher.account)
        .await?
        .map_err(staff_failure)?;
    for world in &worlds {
        state.waiters.wake(world);
    }
    tracing::warn!(account = %teacher.account, teacher = %slip.account, "account of a teacher ordered");
    let no_store = AppendHeaders([(axum::http::header::CACHE_CONTROL, "no-store")]);
    Ok((no_store, Json(AccessSlips { slips: vec![slip] })))
}

/// Has every world set a new start password for a teacher. Accounts of
/// the school administration are never changed from here.
#[utoipa::path(
    post,
    path = "/api/web/v1/staff/{account}/password",
    params(("account" = String, Path, description = "Account name of the teacher")),
    responses(
        (status = 200, description = "The access slip with the new password", body = AccessSlips),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration, or the account is protected (forbidden)", body = ApiError),
        (status = 404, description = "No such teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn reset_staff_password(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(account): Path<String>,
) -> Result<impl IntoResponse, Failure> {
    school_admin_only(&state, &teacher.account).await?;
    let (slip, worlds) = staff::reset_password(&state.db, &account, &teacher.account)
        .await?
        .map_err(staff_failure)?;
    for world in &worlds {
        state.waiters.wake(world);
    }
    tracing::warn!(account = %teacher.account, teacher = %slip.account, "new password for a teacher ordered");
    let no_store = AppendHeaders([(axum::http::header::CACHE_CONTROL, "no-store")]);
    Ok((no_store, Json(AccessSlips { slips: vec![slip] })))
}

/// Orders every world to delete the account of a teacher. The backend
/// deletes address, web access and assignments when the first world
/// reports that it did. It cannot be undone.
#[utoipa::path(
    post,
    path = "/api/web/v1/staff/{account}/removal",
    params(("account" = String, Path, description = "Account name of the teacher")),
    request_body = RemovalRequest,
    responses(
        (status = 200, description = "The accounts of the teachers, with the order on its way", body = StaffList),
        (status = 400, description = "The request does not carry the account name as confirmation (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration, or the account is protected (forbidden)", body = ApiError),
        (status = 404, description = "No such teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn remove_staff(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(account): Path<String>,
    wanted: Result<Json<RemovalRequest>, JsonRejection>,
) -> Result<Json<StaffList>, Failure> {
    let wanted = body(wanted)?;
    school_admin_only(&state, &teacher.account).await?;
    if wanted.confirm != account {
        return Err(Failure::invalid_request(
            "the request does not carry the account name as confirmation",
        ));
    }
    let worlds = staff::remove(&state.db, &account, &teacher.account)
        .await?
        .map_err(staff_failure)?;
    for world in &worlds {
        state.waiters.wake(world);
    }
    tracing::warn!(account = %teacher.account, teacher = %account, "deleting the account of a teacher ordered");
    staff_of(&state).await
}

/// Orders the world to lock or unlock choosing a display name for a
/// student. A lock does not take the name away.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/students/{account}/display-name/lock",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "Account name of the student"),
    ),
    request_body = DisplayLock,
    responses(
        (status = 200, description = "The students of the group", body = Students),
        (status = 400, description = "The request cannot be read (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or no such account that exists in the world (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn lock_display_name(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account)): Path<(String, String)>,
    wanted: Result<Json<DisplayLock>, JsonRejection>,
) -> Result<Json<Students>, Failure> {
    let wanted = body(wanted)?;
    group_of(&state, &teacher.account, &id).await?;
    if !display_names::set_locked(&state.db, &id, &account, wanted.locked, &teacher.account).await?
    {
        return Err(Failure::not_found(
            "no such account that exists in the world",
        ));
    }
    state.waiters.wake(&id);
    tracing::info!(account = %teacher.account, group = %id, student = %account, locked = wanted.locked, "lock of a display name ordered");
    Ok(Json(Students {
        students: students::list(&state.db, &id).await?,
    }))
}

/// Shows what happened to the display name of a student, newest first.
/// It is read from a protocol of the world and is deleted with it.
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}/students/{account}/display-names",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "Account name of the student"),
    ),
    responses(
        (status = 200, description = "The history of the display names", body = DisplayNameHistory),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or no such account that exists in the world (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn display_name_history(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account)): Path<(String, String)>,
) -> Result<Json<DisplayNameHistory>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    match display_names::history(&state.db, &id, &account).await? {
        Some(entries) => Ok(Json(DisplayNameHistory { entries })),
        None => Err(Failure::not_found(
            "no such account that exists in the world",
        )),
    }
}

/// Lets only the administration of the school through.
async fn school_admin(state: &AppState, account: &str) -> Result<(), Failure> {
    if groups::is_school_admin(&state.db, account).await? {
        Ok(())
    } else {
        Err(Failure::forbidden(
            "only the school administration closes the year",
        ))
    }
}

/// Shows what closing the year would delete per group, how far the
/// worlds are with the last one, and when the year was closed before.
#[utoipa::path(
    get,
    path = "/api/web/v1/year-end",
    responses(
        (status = 200, description = "What would be deleted, and the years that were closed", body = YearEnd),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn show_year_end(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
) -> Result<Json<YearEnd>, Failure> {
    school_admin(&state, &teacher.account).await?;
    Ok(Json(year_end::overview(&state.db).await?))
}

/// Closes the year for the whole school: deletes all protocols and the
/// list of exports in the backend and orders every world to delete its
/// own protocols. What students have reached stays. It cannot be undone.
#[utoipa::path(
    post,
    path = "/api/web/v1/year-end",
    request_body = YearEndRequest,
    responses(
        (status = 200, description = "The year is closed; the worlds delete as soon as they answer", body = YearEnd),
        (status = 400, description = "The request does not carry the confirmation (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "Not the school administration (forbidden)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn close_year(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    wanted: Result<Json<YearEndRequest>, JsonRejection>,
) -> Result<Json<YearEnd>, Failure> {
    let wanted = body(wanted)?;
    school_admin(&state, &teacher.account).await?;
    if wanted.confirm != YEAR_END_CONFIRMATION {
        return Err(Failure::invalid_request(
            "the request does not carry the confirmation",
        ));
    }
    let groups = year_end::close(&state.db, clock::now(), &teacher.account).await?;
    for group in &groups {
        state.waiters.wake(group);
        state.changes.tell(group, &[ChangeTopic::Protocols]);
    }
    tracing::warn!(account = %teacher.account, groups = groups.len(), "the year was closed: protocols deleted");
    Ok(Json(year_end::overview(&state.db).await?))
}

/// What narrows a protocol down, and which part of it is wanted.
#[derive(Debug, Deserialize)]
pub struct ProtocolQuery {
    account: Option<String>,
    since: Option<i64>,
    before: Option<i64>,
    after: Option<i64>,
}

impl ProtocolQuery {
    fn filter(&self) -> protocols::Filter {
        protocols::Filter {
            account: self
                .account
                .as_deref()
                .map(str::trim)
                .filter(|account| !account.is_empty())
                .map(str::to_owned),
            since: self.since,
        }
    }
}

/// Checks that a teacher may read a protocol of a group and returns the
/// group. The protocol of the desk shows what teachers did: only the
/// administration of the school reads it.
async fn protocol_of(
    state: &AppState,
    account: &str,
    id: &str,
    protocol: &str,
) -> Result<Group, Failure> {
    let group = group_of(state, account, id).await?;
    if protocols::columns(protocol).is_none() {
        return Err(Failure::not_found("no such protocol"));
    }
    if protocols::is_restricted(protocol) && !groups::is_school_admin(&state.db, account).await? {
        return Err(Failure::forbidden(
            "only the school administration reads what teachers did",
        ));
    }
    Ok(group)
}

/// Shows a part of a protocol of the world of a group, newest entries
/// first: chat, signs, rewards, desk or names. A page has 100 entries.
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}/protocols/{protocol}",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("protocol" = String, Path, description = "chat, signs, rewards, names, desk or exports"),
        ("account" = Option<String>, Query, description = "Only entries of this account"),
        ("since" = Option<i64>, Query, description = "Only entries from this time on, in seconds since 1970"),
        ("before" = Option<i64>, Query, description = "Only entries older than the one with this id: the next page"),
        ("after" = Option<i64>, Query, description = "Only entries that arrived after the one with this id"),
    ),
    responses(
        (status = 200, description = "A part of the protocol", body = ProtocolPage),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "The protocol of the desk or of the exports, and not the school administration (forbidden)", body = ApiError),
        (status = 404, description = "No such group, not one of the teacher, or no such protocol (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn show_protocol(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, protocol)): Path<(String, String)>,
    Query(query): Query<ProtocolQuery>,
) -> Result<Json<ProtocolPage>, Failure> {
    protocol_of(&state, &teacher.account, &id, &protocol).await?;
    let part = match (query.before, query.after) {
        (Some(id), _) => protocols::Part::Before(id),
        (None, Some(id)) => protocols::Part::After(id),
        (None, None) => protocols::Part::Newest,
    };
    protocols::page(&state.db, &id, &protocol, &query.filter(), part)
        .await?
        .map(Json)
        .ok_or_else(|| Failure::not_found("no such protocol"))
}

/// Returns the filtered entries of a protocol as a CSV file to download,
/// oldest first, with times in UTC and cells separated by semicolons.
/// The file leaves the platform: who exports it answers for it, and
/// every export is written into the protocol "exports".
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}/protocols/{protocol}/export",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("protocol" = String, Path, description = "chat, signs, rewards, names, desk or exports"),
        ("account" = Option<String>, Query, description = "Only entries of this account"),
        ("since" = Option<i64>, Query, description = "Only entries from this time on, in seconds since 1970"),
    ),
    responses(
        (status = 200, description = "The entries as a CSV file", content_type = "text/csv", body = String),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 403, description = "The protocol of the desk or of the exports, and not the school administration (forbidden)", body = ApiError),
        (status = 404, description = "No such group, not one of the teacher, or no such protocol (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn export_protocol(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, protocol)): Path<(String, String)>,
    Query(query): Query<ProtocolQuery>,
) -> Result<Response, Failure> {
    let group = protocol_of(&state, &teacher.account, &id, &protocol).await?;
    let filter = query.filter();
    let (file, entries) = protocols::export(&state.db, &id, &protocol, &filter)
        .await?
        .ok_or_else(|| Failure::not_found("no such protocol"))?;
    // The file leaves the platform: that it was made is written down,
    // also when the file is this very list.
    protocols::record_export(
        &state.db,
        &id,
        clock::now(),
        &teacher.account,
        &protocol,
        &filter,
        entries,
    )
    .await?;
    state.changes.tell(&id, &[ChangeTopic::Protocols]);
    // The name of the group goes into the file name, without anything a
    // header or a file system could trip over.
    let group_name: String = group
        .name
        .chars()
        .filter(|character| character.is_ascii_alphanumeric() || *character == '-')
        .collect();
    let disposition = format!("attachment; filename=\"protokoll-{protocol}-{group_name}.csv\"");
    tracing::info!(account = %teacher.account, group = %id, %protocol, filtered_by = ?filter.account, "protocol exported");
    Ok((
        [
            (CONTENT_TYPE, "text/csv; charset=utf-8".to_owned()),
            (CONTENT_DISPOSITION, disposition),
            (CACHE_CONTROL, "no-store".to_owned()),
        ],
        file,
    )
        .into_response())
}

/// Returns the group a path of this interface is about, if any.
fn group_in(path: &str) -> Option<&str> {
    let rest = path.split_once("/groups/")?.1;
    let id = rest.split('/').next().unwrap_or_default();
    (!id.is_empty()).then_some(id)
}

/// After every request that changed something about a group, tells the
/// pages that have the group open. One place for all ways, so none is
/// forgotten: a page that loads once too often does no harm.
async fn tell_changes(State(state): State<AppState>, request: Request, next: Next) -> Response {
    let changed = (request.method() != Method::GET)
        .then(|| group_in(request.uri().path()).map(str::to_owned))
        .flatten();
    let response = next.run(request).await;
    if let Some(group) = changed {
        if response.status().is_success() {
            state.changes.tell(&group, &changes::ALL);
        }
    }
    response
}

/// What a page that watches a group is waiting for.
struct Watch {
    signals: broadcast::Receiver<ChangeTopic>,
    /// Topics still to send after the page fell behind.
    missed: VecDeque<ChangeTopic>,
    stopped: Pin<Box<dyn Future<Output = ()> + Send>>,
    session_over: Pin<Box<tokio::time::Sleep>>,
}

fn change_event(topic: ChangeTopic) -> Result<SseEvent, Infallible> {
    Ok(SseEvent::default().event("change").data(topic.as_str()))
}

/// Keeps the request open and sends an event named "change" whenever a
/// part of the group changed. Its data is one of the words of
/// `ChangeTopic`, never the changed data itself: the page loads that
/// part again. The request ends when the session does, and when the
/// backend stops.
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}/changes",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "A stream of server-sent events named \"change\", each with a ChangeTopic as data", content_type = "text/event-stream", body = String),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or not one of the teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn watch_changes(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<Sse<impl Stream<Item = Result<SseEvent, Infallible>>>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    let left = u64::try_from(teacher.expires_at - clock::now()).unwrap_or(0);
    let watch = Watch {
        signals: state.changes.listen(&id),
        missed: VecDeque::new(),
        stopped: Box::pin(state.changes.stopped()),
        session_over: Box::pin(tokio::time::sleep(Duration::from_secs(left))),
    };
    let events = stream::unfold(watch, |mut watch| async move {
        if let Some(topic) = watch.missed.pop_front() {
            return Some((change_event(topic), watch));
        }
        tokio::select! {
            signal = watch.signals.recv() => match signal {
                Ok(topic) => Some((change_event(topic), watch)),
                // The page fell behind: it loads everything again.
                Err(broadcast::error::RecvError::Lagged(_)) => {
                    watch.missed.extend(&changes::ALL[1..]);
                    Some((change_event(changes::ALL[0]), watch))
                }
                Err(broadcast::error::RecvError::Closed) => None,
            },
            () = &mut watch.stopped => None,
            () = &mut watch.session_over => None,
        }
    });
    Ok(Sse::new(events).keep_alive(KeepAlive::new().interval(Duration::from_secs(15))))
}

/// Shows where the students of a group stand: level and workload per
/// module, and the trophies. It is what the world reported last.
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}/progress",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "The modules of the world and the students whose accounts exist", body = GroupProgress),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or not one of the teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn show_progress(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<Json<GroupProgress>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    Ok(Json(progress::of_group(&state.db, &id).await?))
}

/// Returns the reward table of a group: what is paid for which
/// occasion, and the items that can be chosen.
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}/rewards",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "The reward table of the group", body = GroupRewards),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or not one of the teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn show_rewards(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<Json<GroupRewards>, Failure> {
    group_of(&state, &teacher.account, &id).await?;
    Ok(Json(crate::rewards::of_group(&state.db, &id).await?))
}

/// Orders a new reward table for a group, or the default of its world
/// if no table is given. The world checks it, takes it as a whole or
/// not at all, and reports the table it has then. It counts from the
/// next reward on.
#[utoipa::path(
    put,
    path = "/api/web/v1/groups/{id}/rewards",
    params(("id" = String, Path, description = "Identifier of the group")),
    request_body = RewardsChange,
    responses(
        (status = 200, description = "The table that counts, with the change on its way", body = GroupRewards),
        (status = 400, description = "A count or the daily limit is out of range, an item cannot be chosen, or the world has not reported its table yet (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or not one of the teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn change_rewards(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
    wanted: Result<Json<RewardsChange>, JsonRejection>,
) -> Result<Json<GroupRewards>, Failure> {
    let wanted = body(wanted)?;
    group_of(&state, &teacher.account, &id).await?;
    match crate::rewards::order(&state.db, &id, wanted.table, &teacher.account).await? {
        Ok(()) => {}
        Err(crate::rewards::OrderError::Invalid) => {
            return Err(Failure::invalid_request(
                "a count or the daily limit is out of range, or an item cannot be chosen",
            ))
        }
        Err(crate::rewards::OrderError::NotReported) => {
            return Err(Failure::invalid_request(
                "the world has not reported its reward table yet",
            ))
        }
    }
    state.waiters.wake(&id);
    tracing::info!(account = %teacher.account, group = %id, "reward table ordered");
    Ok(Json(crate::rewards::of_group(&state.db, &id).await?))
}

/// Orders the level new students start a module on. It counts for
/// every student the world has stored nothing about in this module;
/// who has started stays where they are. The world makes the change and
/// reports it with its modules; until then the answer shows the old
/// level with the change as pending.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/progress/start/{module}",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("module" = String, Path, description = "Id of the module"),
    ),
    request_body = StartLevelChange,
    responses(
        (status = 200, description = "The progress of the group, with the change on its way", body = GroupProgress),
        (status = 400, description = "The module has no such level (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, not one of the teacher, or no such module (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn change_start_level(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, module)): Path<(String, String)>,
    wanted: Result<Json<StartLevelChange>, JsonRejection>,
) -> Result<Json<GroupProgress>, Failure> {
    let wanted = body(wanted)?;
    group_of(&state, &teacher.account, &id).await?;
    match progress::set_start_level(&state.db, &id, &module, wanted.level, &teacher.account).await?
    {
        Ok(()) => {}
        Err(ChangeProgressError::BadLevel) => {
            return Err(Failure::invalid_request("the module has no such level"))
        }
        Err(_) => return Err(Failure::not_found("no such module")),
    }
    state.waiters.wake(&id);
    tracing::info!(account = %teacher.account, group = %id, %module, level = wanted.level, "start level ordered");
    Ok(Json(progress::of_group(&state.db, &id).await?))
}

/// Returns where the students of a group stand as a CSV file to
/// download: one line per student and module, cells separated by
/// semicolons. The file leaves the platform: who exports it answers for
/// it, and the export is written into the protocol "exports".
#[utoipa::path(
    get,
    path = "/api/web/v1/groups/{id}/progress/export",
    params(("id" = String, Path, description = "Identifier of the group")),
    responses(
        (status = 200, description = "The progress as a CSV file", content_type = "text/csv", body = String),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, or not one of the teacher (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn export_progress(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path(id): Path<String>,
) -> Result<Response, Failure> {
    let group = group_of(&state, &teacher.account, &id).await?;
    let (file, lines) = progress::export(&state.db, &id).await?;
    protocols::record_export(
        &state.db,
        &id,
        clock::now(),
        &teacher.account,
        progress::EXPORT_NAME,
        &protocols::Filter::default(),
        lines,
    )
    .await?;
    state.changes.tell(&id, &[ChangeTopic::Protocols]);
    let group_name: String = group
        .name
        .chars()
        .filter(|character| character.is_ascii_alphanumeric() || *character == '-')
        .collect();
    let disposition = format!("attachment; filename=\"fortschritt-{group_name}.csv\"");
    tracing::info!(account = %teacher.account, group = %id, "progress exported");
    Ok((
        [
            (CONTENT_TYPE, "text/csv; charset=utf-8".to_owned()),
            (CONTENT_DISPOSITION, disposition),
            (CACHE_CONTROL, "no-store".to_owned()),
        ],
        file,
    )
        .into_response())
}

/// Orders a new level, a lock or both for a student in a module. The
/// world makes the change and reports the new state; until then the
/// answer shows the old state with the change as pending.
#[utoipa::path(
    post,
    path = "/api/web/v1/groups/{id}/progress/{account}/{module}",
    params(
        ("id" = String, Path, description = "Identifier of the group"),
        ("account" = String, Path, description = "Account name of the student"),
        ("module" = String, Path, description = "Id of the module"),
    ),
    request_body = ProgressChange,
    responses(
        (status = 200, description = "The progress of the group, with the change on its way", body = GroupProgress),
        (status = 400, description = "No such level, or nothing to change (invalid_request)", body = ApiError),
        (status = 401, description = "Not logged in (unauthorized)", body = ApiError),
        (status = 404, description = "No such group, no such account that exists in the world, or no such module (not_found)", body = ApiError),
    ),
    security(("session" = []))
)]
pub async fn change_progress(
    State(state): State<AppState>,
    Teacher(teacher): Teacher,
    Path((id, account, module)): Path<(String, String, String)>,
    wanted: Result<Json<ProgressChange>, JsonRejection>,
) -> Result<Json<GroupProgress>, Failure> {
    let wanted = body(wanted)?;
    group_of(&state, &teacher.account, &id).await?;
    progress::change(&state.db, &id, &account, &module, &wanted, &teacher.account)
        .await?
        .map_err(|error| match error {
            ChangeProgressError::NoStudent => {
                Failure::not_found("no such account that exists in the world")
            }
            ChangeProgressError::NoModule => Failure::not_found("no such module"),
            ChangeProgressError::BadLevel => {
                Failure::invalid_request("the module has no such level")
            }
            ChangeProgressError::Empty => Failure::invalid_request("nothing to change"),
        })?;
    state.waiters.wake(&id);
    tracing::info!(account = %teacher.account, group = %id, student = %account, module = %module, "progress change ordered");
    Ok(Json(progress::of_group(&state.db, &id).await?))
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
