//! The signals that tell open pages about changes of a group, and the
//! end of requests that are kept open when the backend stops. Called
//! without a network.

use std::time::Duration;

use axum::body::Body;
use axum::http::{header, HeaderMap, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::mail::Mailer;
use lep_backend::{clock, db, groups, logins, teachers, worlds};
use lep_protocol::web::GroupChange;
use lep_protocol::world::{WebAccessAction, WebAccessRequest};
use serde_json::{json, Value};
use sqlx::SqlitePool;
use tower::ServiceExt;

struct Setup {
    state: AppState,
    /// Group "7b" with its key. "lehrer1" is its teacher.
    first: String,
    key: String,
    /// Group "8a", without a teacher.
    second: String,
}

async fn log_in(pool: &SqlitePool, account: &str) -> String {
    let email = format!("{account}@schule.example");
    let set = WebAccessRequest {
        account: account.to_owned(),
        action: WebAccessAction::Set,
        email: Some(email.clone()),
    };
    let now = clock::now();
    let Some(teachers::Change::Mail { token, .. }) =
        teachers::request(pool, &set, now).await.unwrap()
    else {
        panic!("expected a mail");
    };
    teachers::confirm(pool, &token, now).await.unwrap().unwrap();
    let link = logins::request_link(pool, &email, now)
        .await
        .unwrap()
        .unwrap();
    logins::redeem(pool, &link.token, now)
        .await
        .unwrap()
        .unwrap()
        .token
}

impl Setup {
    async fn new() -> Self {
        let pool = db::open_in_memory().await.unwrap();
        let (first, key) = worlds::add(&pool, "7b").await.unwrap();
        let (second, _) = worlds::add(&pool, "8a").await.unwrap();
        let names = |list: &[&str]| {
            list.iter()
                .map(|name| (*name).to_owned())
                .collect::<Vec<_>>()
        };
        teachers::set_holders(&pool, &first.id, &names(&["leitung", "lehrer1", "lehrer2"]))
            .await
            .unwrap();
        groups::set_school_admins(&pool, &first.id, &names(&["leitung"]))
            .await
            .unwrap();
        let assign = GroupChange {
            name: None,
            teachers: Some(names(&["lehrer1"])),
            address: None,
        };
        groups::change(&pool, &first.id, &assign)
            .await
            .unwrap()
            .unwrap();
        Self {
            state: AppState::with(pool, Mailer::memory(), "https://lep.schule.example"),
            first: first.id,
            key,
            second: second.id,
        }
    }

    async fn call(
        &self,
        method: Method,
        path: &str,
        auth: Option<(header::HeaderName, String)>,
        body: Option<Value>,
    ) -> (StatusCode, Value, HeaderMap) {
        let mut request = Request::builder().method(method).uri(path);
        if let Some((name, value)) = auth {
            request = request.header(name, value);
        }
        let body = match body {
            Some(json) => {
                request = request.header(header::CONTENT_TYPE, "application/json");
                Body::from(json.to_string())
            }
            None => Body::empty(),
        };
        let response = app::router(self.state.clone())
            .oneshot(request.body(body).unwrap())
            .await
            .unwrap();
        let status = response.status();
        let headers = response.headers().clone();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        (
            status,
            serde_json::from_slice(&bytes).unwrap_or(Value::Null),
            headers,
        )
    }

    /// Calls as a teacher in the browser.
    async fn web(
        &self,
        method: Method,
        path: &str,
        session: &str,
        body: Option<Value>,
    ) -> (StatusCode, Value) {
        let cookie = (header::COOKIE, format!("lep_session={session}"));
        let (status, json, _) = self.call(method, path, Some(cookie), body).await;
        (status, json)
    }

    /// Calls as the world of the first group.
    async fn world(&self, method: Method, path: &str, body: Option<Value>) -> (StatusCode, Value) {
        let key = (header::AUTHORIZATION, format!("Bearer {}", self.key));
        let (status, json, _) = self.call(method, path, Some(key), body).await;
        (status, json)
    }
}

impl Setup {
    /// Opens the stream of changes of a group and returns its body.
    async fn watch(&self, group: &str, session: &str) -> (StatusCode, Body) {
        let request = Request::builder()
            .uri(format!("/api/web/v1/groups/{group}/changes"))
            .header(header::COOKIE, format!("lep_session={session}"))
            .body(Body::empty())
            .unwrap();
        let response = app::router(self.state.clone())
            .oneshot(request)
            .await
            .unwrap();
        (response.status(), response.into_body())
    }
}

/// Reads the next event of a stream, or `None` if it ended. Panics if
/// nothing comes.
async fn next_event(body: &mut Body) -> Option<String> {
    let frame = tokio::time::timeout(Duration::from_secs(2), body.frame())
        .await
        .expect("the stream sent nothing");
    frame.map(|frame| String::from_utf8(frame.unwrap().into_data().unwrap().to_vec()).unwrap())
}

/// Says whether a stream stays silent for a moment.
async fn is_silent(body: &mut Body) -> bool {
    tokio::time::timeout(Duration::from_millis(100), body.frame())
        .await
        .is_err()
}

#[tokio::test]
async fn a_page_hears_what_the_world_reports() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let (status, mut stream) = setup.watch(&setup.first, &teacher).await;
    assert_eq!(status, StatusCode::OK);
    assert!(is_silent(&mut stream).await);

    setup
        .world(
            Method::POST,
            "/api/world/v1/events",
            Some(json!({ "events": [
                { "id": "m1", "kind": "modules", "time": 1700000000, "payload": { "modules": [] } },
                { "id": "n1", "kind": "display_name", "time": 1700000000,
                  "payload": { "account": "klugeEule", "name": "Lena" } },
                { "id": "x1", "kind": "nonsense", "time": 1700000000, "payload": {} }
            ] })),
        )
        .await;
    // Only the kind of part, never the data.
    assert_eq!(
        next_event(&mut stream).await.unwrap(),
        "event: change\ndata: progress\n\n"
    );
    assert_eq!(
        next_event(&mut stream).await.unwrap(),
        "event: change\ndata: students\n\n"
    );
    assert_eq!(
        next_event(&mut stream).await.unwrap(),
        "event: change\ndata: progress\n\n"
    );
    // The event that was refused changed nothing.
    assert!(is_silent(&mut stream).await);

    // The same event again is a duplicate: nothing changed.
    setup
        .world(
            Method::POST,
            "/api/world/v1/events",
            Some(json!({ "events": [
                { "id": "m1", "kind": "modules", "time": 1700000000, "payload": { "modules": [] } }
            ] })),
        )
        .await;
    assert!(is_silent(&mut stream).await);
}

#[tokio::test]
async fn a_page_hears_what_another_teacher_changes_and_what_the_world_answers() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let administration = log_in(&setup.state.db, "leitung").await;
    let (_, mut stream) = setup.watch(&setup.first, &teacher).await;
    let (_, mut elsewhere) = setup.watch(&setup.second, &administration).await;

    let students = format!("/api/web/v1/groups/{}/students", setup.first);
    let (status, _) = setup
        .web(
            Method::POST,
            &students,
            &administration,
            Some(json!({ "count": 1 })),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    for topic in ["group", "students", "progress"] {
        assert_eq!(
            next_event(&mut stream).await.unwrap(),
            format!("event: change\ndata: {topic}\n\n")
        );
    }
    // Reading changes nothing, and neither does a request that failed.
    setup
        .web(Method::GET, &students, &administration, None)
        .await;
    let (status, _) = setup
        .web(
            Method::POST,
            &students,
            &administration,
            Some(json!({ "count": 0 })),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(is_silent(&mut stream).await);

    // The world answers a job: what waited is done.
    setup
        .web(
            Method::POST,
            &format!("{students}/create"),
            &administration,
            None,
        )
        .await;
    for _ in 0..3 {
        next_event(&mut stream).await.unwrap();
    }
    let (_, jobs) = setup
        .world(Method::GET, "/api/world/v1/jobs?wait=0", None)
        .await;
    let result = format!(
        "/api/world/v1/jobs/{}/result",
        jobs["jobs"][0]["id"].as_str().unwrap()
    );
    setup
        .world(
            Method::POST,
            &result,
            Some(json!({ "ok": true, "message": "" })),
        )
        .await;
    assert_eq!(
        next_event(&mut stream).await.unwrap(),
        "event: change\ndata: students\n\n"
    );
    assert_eq!(
        next_event(&mut stream).await.unwrap(),
        "event: change\ndata: progress\n\n"
    );
    // The page of another group heard none of this.
    assert!(is_silent(&mut elsewhere).await);
}

#[tokio::test]
async fn only_the_teachers_of_a_group_and_the_administration_may_listen() {
    let setup = Setup::new().await;
    let stranger = log_in(&setup.state.db, "lehrer2").await;
    let administration = log_in(&setup.state.db, "leitung").await;
    let (status, _) = setup.watch(&setup.first, &stranger).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = setup.watch(&setup.first, "no-session").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = setup.watch("no-such-group", &administration).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = setup.watch(&setup.first, &administration).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn the_stream_ends_with_the_session() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    // The session is over in a moment.
    sqlx::query("UPDATE sessions SET expires_at = ?")
        .bind(clock::now() + 1)
        .execute(&setup.state.db)
        .await
        .unwrap();
    let (status, mut stream) = setup.watch(&setup.first, &teacher).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(next_event(&mut stream).await, None);
}

#[tokio::test]
async fn requests_that_are_kept_open_end_when_the_backend_stops() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let (_, mut stream) = setup.watch(&setup.first, &teacher).await;

    // A world waits for jobs, as long as it may.
    let waiting = tokio::spawn({
        let router = app::router(setup.state.clone());
        let key = format!("Bearer {}", setup.key);
        async move {
            let request = Request::builder()
                .uri("/api/world/v1/jobs?wait=25")
                .header(header::AUTHORIZATION, key)
                .body(Body::empty())
                .unwrap();
            router.oneshot(request).await.unwrap().status()
        }
    });
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert!(!waiting.is_finished());

    setup.state.changes.stop();
    assert_eq!(next_event(&mut stream).await, None);
    let status = tokio::time::timeout(Duration::from_secs(2), waiting)
        .await
        .expect("the world still waits")
        .unwrap();
    assert_eq!(status, StatusCode::OK);
    // Who comes afterwards does not wait either.
    let (_, mut late) = setup.watch(&setup.first, &teacher).await;
    assert_eq!(next_event(&mut late).await, None);
}
