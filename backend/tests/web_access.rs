//! Web access of a teacher from the desk to the confirmed address, called
//! without a network.

use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::mail::Mailer;
use lep_backend::{db, worlds};
use serde_json::{json, Value};
use tower::ServiceExt;

struct Setup {
    state: AppState,
    key: String,
    next_event: std::cell::Cell<u32>,
}

impl Setup {
    async fn new() -> Self {
        let pool = db::open_in_memory().await.unwrap();
        let (_, key) = worlds::add(&pool, "7b").await.unwrap();
        Self {
            state: AppState::with(pool, Mailer::memory(), "https://lep.example"),
            key,
            next_event: std::cell::Cell::new(1),
        }
    }

    async fn call(
        &self,
        method: Method,
        path: &str,
        key: Option<&str>,
        body: Option<Value>,
    ) -> (StatusCode, Value) {
        let mut request = Request::builder().method(method).uri(path);
        if let Some(key) = key {
            request = request.header(header::AUTHORIZATION, format!("Bearer {key}"));
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
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        (
            status,
            serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        )
    }

    /// Sends one event as the world and returns its outcome.
    async fn event(&self, kind: &str, payload: Value) -> String {
        let number = self.next_event.get();
        self.next_event.set(number + 1);
        let body = json!({ "events": [
            { "id": format!("e{number}"), "kind": kind, "time": 1700000000, "payload": payload }
        ] });
        let (status, json) = self
            .call(
                Method::POST,
                "/api/world/v1/events",
                Some(&self.key),
                Some(body),
            )
            .await;
        assert_eq!(status, StatusCode::OK);
        json["results"][0]["outcome"].as_str().unwrap().to_owned()
    }

    /// Fetches the waiting jobs as the world, reports them done and
    /// returns the payloads of the status jobs.
    async fn status_jobs(&self) -> Vec<Value> {
        let (status, json) = self
            .call(Method::GET, "/api/world/v1/jobs", Some(&self.key), None)
            .await;
        assert_eq!(status, StatusCode::OK);
        let mut payloads = Vec::new();
        for job in json["jobs"].as_array().unwrap() {
            assert_eq!(job["kind"], "web_access_status");
            payloads.push(job["payload"].clone());
            let path = format!("/api/world/v1/jobs/{}/result", job["id"].as_str().unwrap());
            let done = json!({ "ok": true, "message": "" });
            let (status, _) = self
                .call(Method::POST, &path, Some(&self.key), Some(done))
                .await;
            assert_eq!(status, StatusCode::OK);
        }
        payloads
    }

    async fn confirm(&self, token: &str) -> (StatusCode, Value) {
        self.call(
            Method::POST,
            "/api/web/v1/confirm",
            None,
            Some(json!({ "token": token })),
        )
        .await
    }

    /// Returns the token of the link in the newest mail.
    fn last_token(&self) -> String {
        let mails = self.state.mailer.kept();
        let body = &mails.last().expect("no mail went out").body;
        let start = body.find("https://lep.example/confirm?token=").unwrap();
        body[start..]
            .split_whitespace()
            .next()
            .unwrap()
            .rsplit('=')
            .next()
            .unwrap()
            .to_owned()
    }
}

#[tokio::test]
async fn a_teacher_sets_up_web_access_and_confirms_the_address() {
    let setup = Setup::new().await;

    // The world says who holds the privilege and learns how they stand.
    assert_eq!(
        setup
            .event("teachers", json!({ "accounts": ["lehrer1"] }))
            .await,
        "accepted"
    );
    assert_eq!(
        setup.status_jobs().await,
        vec![json!({ "account": "lehrer1" })]
    );

    // The teacher enters an address at the desk.
    let set = json!({ "account": "lehrer1", "action": "set", "email": "Anna@Schule.Example" });
    assert_eq!(setup.event("web_access", set).await, "accepted");
    let mails = setup.state.mailer.kept();
    assert_eq!(mails.len(), 1);
    assert_eq!(mails[0].to, "anna@schule.example");
    assert_eq!(
        setup.status_jobs().await,
        vec![json!({ "account": "lehrer1", "pending": "a…@schule.example" })]
    );

    // The link from the mail confirms it, once.
    let token = setup.last_token();
    let (status, json) = setup.confirm(&token).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json, json!({ "account": "lehrer1" }));
    assert_eq!(
        setup.status_jobs().await,
        vec![json!({ "account": "lehrer1", "address": "a…@schule.example" })]
    );

    let (status, json) = setup.confirm(&token).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["code"], "invalid_token");
    assert!(setup.status_jobs().await.is_empty());

    // Removing it forgets the address.
    let remove = json!({ "account": "lehrer1", "action": "remove" });
    assert_eq!(setup.event("web_access", remove).await, "accepted");
    assert_eq!(
        setup.status_jobs().await,
        vec![json!({ "account": "lehrer1" })]
    );
}

#[tokio::test]
async fn nothing_happens_for_accounts_the_world_did_not_name() {
    let setup = Setup::new().await;
    let set = json!({ "account": "schueler1", "action": "set", "email": "x@schule.example" });
    assert_eq!(setup.event("web_access", set.clone()).await, "accepted");
    assert!(setup.state.mailer.kept().is_empty());
    assert!(setup.status_jobs().await.is_empty());

    // Once the privilege is gone, the same holds for a former teacher.
    setup
        .event("teachers", json!({ "accounts": ["schueler1"] }))
        .await;
    // A world without teachers sends a payload with nothing left in it.
    let gone = json!({ "events": [
        { "id": "gone", "kind": "teachers", "time": 1700000000, "payload": null }
    ] });
    let (_, answer) = setup
        .call(
            Method::POST,
            "/api/world/v1/events",
            Some(&setup.key),
            Some(gone),
        )
        .await;
    assert_eq!(answer["results"][0]["outcome"], "accepted");
    setup.status_jobs().await;
    assert_eq!(setup.event("web_access", set).await, "accepted");
    assert!(setup.state.mailer.kept().is_empty());
}

#[tokio::test]
async fn requests_that_make_no_sense_are_invalid() {
    let setup = Setup::new().await;
    setup
        .event("teachers", json!({ "accounts": ["lehrer1"] }))
        .await;
    for payload in [
        json!({ "account": "lehrer1", "action": "set" }),
        json!({ "account": "lehrer1", "action": "set", "email": "no address" }),
        json!({ "account": "lehrer1", "action": "explode" }),
        json!({ "account": "not an account", "action": "resend" }),
        json!({ "action": "resend" }),
    ] {
        assert_eq!(setup.event("web_access", payload).await, "invalid");
    }
    assert_eq!(
        setup
            .event("teachers", json!({ "accounts": "lehrer1" }))
            .await,
        "invalid"
    );
    assert!(setup.state.mailer.kept().is_empty());
}

#[tokio::test]
async fn confirming_answers_with_a_code_when_it_fails() {
    let setup = Setup::new().await;
    let (status, json) = setup.confirm("lepc_made_up").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["code"], "invalid_token");

    for body in [json!({}), json!({ "token": 5 }), json!("text")] {
        let (status, json) = setup
            .call(Method::POST, "/api/web/v1/confirm", None, Some(body))
            .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(json["code"], "invalid_request");
    }

    // The same address for two accounts: the first confirmation wins.
    setup
        .event("teachers", json!({ "accounts": ["lehrer1", "lehrer2"] }))
        .await;
    for account in ["lehrer1", "lehrer2"] {
        let set = json!({ "account": account, "action": "set", "email": "anna@schule.example" });
        setup.event("web_access", set).await;
    }
    let second = setup.last_token();
    let mails = setup.state.mailer.kept();
    assert_eq!(mails.len(), 2);
    let first_body = &mails[0].body;
    let start = first_body.find("token=").unwrap() + "token=".len();
    let first = first_body[start..].split_whitespace().next().unwrap();
    assert_eq!(setup.confirm(first).await.0, StatusCode::OK);

    let (status, json) = setup.confirm(&second).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(json["code"], "address_taken");
}
