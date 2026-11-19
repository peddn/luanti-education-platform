//! Closing the year through the interface for the browser. Called
//! without a network.

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

const PATH: &str = "/api/web/v1/year-end";

impl Setup {
    /// Writes a line of chat as the world of the first group.
    async fn chat(&self, id: &str, time: i64) -> Value {
        let (_, json) = self
            .world(
                Method::POST,
                "/api/world/v1/events",
                Some(
                    json!({ "events": [{ "id": id, "kind": "protocol", "time": time,
                    "payload": { "protocol": "chat", "account": "klugeEule",
                        "fields": { "kind": "chat", "text": "hallo" } } }] }),
                ),
            )
            .await;
        json["results"][0]["outcome"].clone()
    }
}

#[tokio::test]
async fn the_administration_closes_the_year() {
    let setup = Setup::new().await;
    let administration = log_in(&setup.state.db, "leitung").await;
    setup.chat("c1", 1700000000).await;
    setup.chat("c2", 1700000060).await;
    let confirmed = Some(json!({ "confirm": "close-the-year" }));

    let (status, before) = setup.web(Method::GET, PATH, &administration, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(before["runs"], json!([]));
    assert_eq!(before["groups"].as_array().unwrap().len(), 2);
    assert_eq!(before["groups"][0]["name"], "7b");
    assert_eq!(before["groups"][1]["id"], setup.second.as_str());
    assert_eq!(before["groups"][0]["protocol_entries"], 2);

    // Not without the word, whatever else the request says.
    for body in [
        json!({}),
        json!({ "confirm": "" }),
        json!({ "confirm": "yes" }),
    ] {
        let (status, json) = setup
            .web(Method::POST, PATH, &administration, Some(body))
            .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(json["code"], "invalid_request");
    }
    let (_, still) = setup.web(Method::GET, PATH, &administration, None).await;
    assert_eq!(still["groups"][0]["protocol_entries"], 2);

    let (status, after) = setup
        .web(Method::POST, PATH, &administration, confirmed)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(after["groups"][0]["protocol_entries"], 0);
    assert_eq!(after["groups"][0]["world"], "pending");
    assert_eq!(after["runs"][0]["account"], "leitung");
    assert_eq!(after["runs"][0]["protocol_entries"], 2);
    assert_eq!(after["runs"][0]["groups"], 2);

    // The protocols are empty for the teachers too.
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let chat = format!("/api/web/v1/groups/{}/protocols/chat", setup.first);
    let (_, page) = setup.web(Method::GET, &chat, &teacher, None).await;
    assert_eq!(page["entries"], json!([]));

    // The world gets the order, does it and says so.
    let (_, jobs) = setup
        .world(Method::GET, "/api/world/v1/jobs?wait=0", None)
        .await;
    assert_eq!(jobs["jobs"][0]["kind"], "clear_protocols");
    assert_eq!(jobs["jobs"][0]["payload"], json!({ "by": "leitung" }));
    let result = format!(
        "/api/world/v1/jobs/{}/result",
        jobs["jobs"][0]["id"].as_str().unwrap()
    );
    setup
        .world(
            Method::POST,
            &result,
            Some(json!({ "ok": true, "message": "cleared" })),
        )
        .await;
    let (_, done) = setup.web(Method::GET, PATH, &administration, None).await;
    assert_eq!(done["groups"][0].get("world"), None);
    // The other group's world has not answered.
    assert_eq!(done["groups"][1]["world"], "pending");

    // An entry from before that the world reports only now is accepted
    // and not kept. New entries are.
    assert_eq!(setup.chat("c3", 1700000120).await, "accepted");
    let (_, page) = setup.web(Method::GET, &chat, &teacher, None).await;
    assert_eq!(page["entries"], json!([]));
    assert_eq!(setup.chat("c4", clock::now() + 5).await, "accepted");
    let (_, page) = setup.web(Method::GET, &chat, &teacher, None).await;
    assert_eq!(page["entries"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn nobody_else_closes_the_year_or_sees_what_it_would_delete() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    setup.chat("c1", 1700000000).await;
    let confirmed = Some(json!({ "confirm": "close-the-year" }));

    for (method, body) in [(Method::GET, None), (Method::POST, confirmed.clone())] {
        let (status, json) = setup
            .web(method.clone(), PATH, &teacher, body.clone())
            .await;
        assert_eq!(status, StatusCode::FORBIDDEN);
        assert_eq!(json["code"], "forbidden");
        let (status, _, _) = setup.call(method, PATH, None, body).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }
    let chat = format!("/api/web/v1/groups/{}/protocols/chat", setup.first);
    let (_, page) = setup.web(Method::GET, &chat, &teacher, None).await;
    assert_eq!(page["entries"].as_array().unwrap().len(), 1);
    let (_, jobs) = setup
        .world(Method::GET, "/api/world/v1/jobs?wait=0", None)
        .await;
    assert_eq!(jobs["jobs"], json!([]));
}
