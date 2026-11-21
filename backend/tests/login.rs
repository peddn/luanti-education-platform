//! Logging in at the web application, called without a network.

use axum::body::Body;
use axum::http::{header, HeaderMap, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::mail::Mailer;
use lep_backend::{db, worlds};
use serde_json::{json, Value};
use tower::ServiceExt;

const EMAIL: &str = "anna@schule.example";

struct Setup {
    state: AppState,
    key: String,
    next_event: std::cell::Cell<u32>,
}

impl Setup {
    /// A backend with one world and the teacher "lehrer1", whose address
    /// is confirmed.
    async fn new(public_url: &str) -> Self {
        let pool = db::open_in_memory().await.unwrap();
        let (_, key) = worlds::add(&pool, "7b").await.unwrap();
        let setup = Self {
            state: AppState::with(pool, Mailer::memory(), public_url),
            key,
            next_event: std::cell::Cell::new(1),
        };
        setup
            .event("teachers", json!({ "accounts": ["lehrer1"] }))
            .await;
        let set = json!({ "account": "lehrer1", "action": "set", "email": EMAIL });
        setup.event("web_access", set).await;
        let token = setup.last_token("confirm");
        let (status, _, _) = setup
            .post("/api/web/v1/confirm", json!({ "token": token }), None)
            .await;
        assert_eq!(status, StatusCode::OK);
        setup
    }

    async fn call(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
        headers: &[(header::HeaderName, String)],
    ) -> (StatusCode, Value, HeaderMap) {
        let mut request = Request::builder().method(method).uri(path);
        for (name, value) in headers {
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

    /// Sends a request as a browser, with the session cookie if there is
    /// one.
    async fn post(
        &self,
        path: &str,
        body: Value,
        session: Option<&str>,
    ) -> (StatusCode, Value, HeaderMap) {
        self.call(Method::POST, path, Some(body), &cookie(session))
            .await
    }

    async fn me(&self, session: Option<&str>) -> (StatusCode, Value) {
        let (status, json, _) = self
            .call(Method::GET, "/api/web/v1/me", None, &cookie(session))
            .await;
        (status, json)
    }

    /// Sends one event as the world.
    async fn event(&self, kind: &str, payload: Value) {
        let number = self.next_event.get();
        self.next_event.set(number + 1);
        let body = json!({ "events": [
            { "id": format!("e{number}"), "kind": kind, "time": 1700000000, "payload": payload }
        ] });
        let key = [(header::AUTHORIZATION, format!("Bearer {}", self.key))];
        let (status, json, _) = self
            .call(Method::POST, "/api/world/v1/events", Some(body), &key)
            .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(json["results"][0]["outcome"], "accepted");
    }

    /// Returns the token of the link to a page in the newest mail.
    fn last_token(&self, page: &str) -> String {
        let mails = self.state.mailer.kept();
        let body = &mails.last().expect("no mail went out").body;
        let marker = format!("/{page}?token=");
        let start = body.find(&marker).expect("the mail has no such link") + marker.len();
        body[start..].split_whitespace().next().unwrap().to_owned()
    }

    /// Asks for a login link and logs in with it. Returns the session
    /// token from the cookie.
    async fn log_in(&self) -> String {
        let (status, _, _) = self
            .post("/api/web/v1/login/link", json!({ "email": EMAIL }), None)
            .await;
        assert_eq!(status, StatusCode::OK);
        let token = self.last_token("login");
        let (status, _, headers) = self
            .post("/api/web/v1/login", json!({ "token": token }), None)
            .await;
        assert_eq!(status, StatusCode::OK);
        session_of(&headers).expect("no session cookie")
    }
}

fn cookie(session: Option<&str>) -> Vec<(header::HeaderName, String)> {
    session
        .map(|token| (header::COOKIE, format!("lep_session={token}")))
        .into_iter()
        .collect()
}

/// Returns the session token a response sets, if it sets a lasting one.
fn session_of(headers: &HeaderMap) -> Option<String> {
    let cookie = headers.get(header::SET_COOKIE)?.to_str().ok()?;
    let value = cookie.split(';').next()?.strip_prefix("lep_session=")?;
    (!value.is_empty()).then(|| value.to_owned())
}

#[tokio::test]
async fn a_teacher_logs_in_with_a_link_and_out_again() {
    let setup = Setup::new("https://lep.example").await;
    assert_eq!(setup.me(None).await.0, StatusCode::UNAUTHORIZED);

    let (status, json, headers) = setup
        .post(
            "/api/web/v1/login/link",
            json!({ "email": " Anna@Schule.Example " }),
            None,
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json, json!({}));
    assert!(headers.get(header::SET_COOKIE).is_none());
    let mail = setup.state.mailer.kept().pop().unwrap();
    assert_eq!(mail.to, EMAIL);
    assert!(mail.body.contains("https://lep.example/login?token=lepl_"));

    let token = setup.last_token("login");
    let (status, json, headers) = setup
        .post("/api/web/v1/login", json!({ "token": token }), None)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["account"], "lehrer1");
    assert_eq!(json["email"], EMAIL);
    assert_eq!(json["worlds"], json!(["7b"]));
    assert!(json["expires_at"].as_i64().unwrap() > 1_700_000_000);

    // The cookie is closed to scripts and to other sites.
    let cookie = headers.get(header::SET_COOKIE).unwrap().to_str().unwrap();
    for part in [
        "HttpOnly",
        "SameSite=Strict",
        "Secure",
        "Path=/api/web",
        "Max-Age=43200",
    ] {
        assert!(cookie.contains(part), "{part} is missing in {cookie}");
    }
    let session = session_of(&headers).unwrap();
    assert!(session.starts_with("leps_"));

    let (status, json) = setup.me(Some(&session)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["account"], "lehrer1");

    // The details of the backend are for teachers only.
    let (status, json, _) = setup
        .call(
            Method::GET,
            "/api/web/v1/status",
            None,
            &[(header::COOKIE, format!("lep_session={session}"))],
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["status"], "ok");
    assert_eq!(json["version"], env!("CARGO_PKG_VERSION"));
    assert_eq!(json["mail"], "terminal");
    // No agent is set up, so there is no game server to describe.
    assert_eq!(json["game_server"], serde_json::Value::Null);
    lep_backend::game_server::rekey(&setup.state.db)
        .await
        .unwrap();
    let report = lep_protocol::agent::AgentReport {
        version: "0.1.0".to_owned(),
        free_disk_bytes: 7,
        template: Some("bdbbf00c8a29".to_owned()),
        worlds: Vec::new(),
        host: None,
    };
    lep_backend::game_server::note_report(&setup.state.db, &report)
        .await
        .unwrap();
    let (_, json, _) = setup
        .call(
            Method::GET,
            "/api/web/v1/status",
            None,
            &[(header::COOKIE, format!("lep_session={session}"))],
        )
        .await;
    assert_eq!(json["game_server"]["connected"], true);
    assert_eq!(json["game_server"]["version"], "0.1.0");
    assert_eq!(json["game_server"]["free_disk_bytes"], 7);
    assert_eq!(json["game_server"]["template"], "bdbbf00c8a29");
    let (status, json, _) = setup
        .call(Method::GET, "/api/web/v1/status", None, &[])
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(json["code"], "unauthorized");

    // The link is used up.
    let (status, json, _) = setup
        .post("/api/web/v1/login", json!({ "token": token }), None)
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["code"], "invalid_token");

    let (status, _, headers) = setup
        .post("/api/web/v1/logout", json!({}), Some(&session))
        .await;
    assert_eq!(status, StatusCode::OK);
    let cookie = headers.get(header::SET_COOKIE).unwrap().to_str().unwrap();
    assert!(cookie.starts_with("lep_session=;"));
    assert!(cookie.contains("Max-Age=0"));
    let (status, json) = setup.me(Some(&session)).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(json["code"], "unauthorized");

    // Logging out without a session is no error.
    assert_eq!(
        setup.post("/api/web/v1/logout", json!({}), None).await.0,
        StatusCode::OK
    );
}

#[tokio::test]
async fn the_answer_does_not_say_whether_an_address_is_known() {
    let setup = Setup::new("http://127.0.0.1:8080").await;
    let mails_before = setup.state.mailer.kept().len();
    let known = setup
        .post("/api/web/v1/login/link", json!({ "email": EMAIL }), None)
        .await;
    for email in ["fremd@schule.example", "no address", ""] {
        let other = setup
            .post("/api/web/v1/login/link", json!({ "email": email }), None)
            .await;
        assert_eq!((other.0, &other.1), (known.0, &known.1), "{email:?}");
    }
    // A second request at once looks the same and sends nothing.
    let again = setup
        .post("/api/web/v1/login/link", json!({ "email": EMAIL }), None)
        .await;
    assert_eq!((again.0, &again.1), (known.0, &known.1));
    assert_eq!(setup.state.mailer.kept().len(), mails_before + 1);

    // Without https the cookie cannot ask for it.
    let token = setup.last_token("login");
    let (_, _, headers) = setup
        .post("/api/web/v1/login", json!({ "token": token }), None)
        .await;
    let cookie = headers.get(header::SET_COOKIE).unwrap().to_str().unwrap();
    assert!(!cookie.contains("Secure"));
}

#[tokio::test]
async fn the_world_can_take_the_access_away_at_once() {
    let setup = Setup::new("https://lep.example").await;
    let session = setup.log_in().await;
    assert_eq!(setup.me(Some(&session)).await.0, StatusCode::OK);

    // The privilege is gone in the only world.
    setup.event("teachers", json!({ "accounts": null })).await;
    assert_eq!(setup.me(Some(&session)).await.0, StatusCode::UNAUTHORIZED);

    // Back again, and then the teacher removes the web access at the desk.
    setup
        .event("teachers", json!({ "accounts": ["lehrer1"] }))
        .await;
    assert_eq!(setup.me(Some(&session)).await.0, StatusCode::OK);
    setup
        .event(
            "web_access",
            json!({ "account": "lehrer1", "action": "remove" }),
        )
        .await;
    assert_eq!(setup.me(Some(&session)).await.0, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn requests_that_cannot_be_read_get_a_code() {
    let setup = Setup::new("https://lep.example").await;
    for (path, body) in [
        ("/api/web/v1/login/link", json!({})),
        ("/api/web/v1/login/link", json!({ "email": 5 })),
        ("/api/web/v1/login", json!({})),
        ("/api/web/v1/login", json!("text")),
    ] {
        let (status, json, _) = setup.post(path, body, None).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{path}");
        assert_eq!(json["code"], "invalid_request");
    }
    let (status, json, _) = setup
        .post(
            "/api/web/v1/login",
            json!({ "token": "lepl_made_up" }),
            None,
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["code"], "invalid_token");
    assert_eq!(
        setup.me(Some("leps_made_up")).await.0,
        StatusCode::UNAUTHORIZED
    );
}
