//! Deleting an account on request through the interfaces for the
//! browser and the world. Called without a network.

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
    leitung: String,
    lehrer1: String,
    lehrer2: String,
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
        sqlx::query(
            "INSERT INTO students (account, world_id, state, created_at, used) VALUES
             ('klugeEule', ?1, 'active', 0, 1), ('stillerBach', ?1, 'active', 0, 0),
             ('froherWal', ?2, 'active', 0, 0)",
        )
        .bind(&first.id)
        .bind(&second.id)
        .execute(&pool)
        .await
        .unwrap();
        Self {
            leitung: log_in(&pool, "leitung").await,
            lehrer1: log_in(&pool, "lehrer1").await,
            lehrer2: log_in(&pool, "lehrer2").await,
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
    fn removal(&self, group: &str, account: &str) -> String {
        format!("/api/web/v1/groups/{group}/students/{account}/removal")
    }

    async fn order(&self, session: &str, account: &str) -> (StatusCode, Value) {
        self.web(
            Method::POST,
            &self.removal(&self.first, account),
            session,
            Some(json!({ "confirm": account })),
        )
        .await
    }

    /// Sends one event as the world of the first group.
    async fn event(&self, id: &str, kind: &str, payload: Value) -> Value {
        let (status, json) = self
            .world(
                Method::POST,
                "/api/world/v1/events",
                Some(json!({ "events": [{ "id": id, "kind": kind, "time": 500,
                    "payload": payload }] })),
            )
            .await;
        assert_eq!(status, StatusCode::OK);
        json["results"][0]["outcome"].clone()
    }
}

fn student<'a>(list: &'a Value, account: &str) -> Option<&'a Value> {
    list["students"]
        .as_array()
        .unwrap()
        .iter()
        .find(|student| student["account"] == account)
}

#[tokio::test]
async fn a_teacher_takes_back_an_unused_account_and_the_world_confirms() {
    let setup = Setup::new().await;
    let (status, list) = setup.order(&setup.lehrer1, "stillerBach").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(student(&list, "stillerBach").unwrap()["removal"], "pending");
    assert_eq!(student(&list, "stillerBach").unwrap()["used"], false);
    assert_eq!(student(&list, "klugeEule").unwrap()["used"], true);

    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(jobs["jobs"][0]["kind"], "remove_account");
    assert_eq!(
        jobs["jobs"][0]["payload"],
        json!({ "account": "stillerBach", "only_unused": true, "by": "lehrer1" })
    );
    let job = jobs["jobs"][0]["id"].as_str().unwrap();
    let (status, _) = setup
        .world(
            Method::POST,
            &format!("/api/world/v1/jobs/{job}/result"),
            Some(json!({ "ok": true, "message": "removed" })),
        )
        .await;
    assert_eq!(status, StatusCode::OK);

    // The account is shown until the world has reported the removal.
    let path = format!("/api/web/v1/groups/{}/students", setup.first);
    let (_, list) = setup.web(Method::GET, &path, &setup.lehrer1, None).await;
    assert_eq!(student(&list, "stillerBach").unwrap()["removal"], "pending");

    let outcome = setup
        .event(
            "e1",
            "account_removed",
            json!({ "account": "stillerBach", "by": "lehrer1" }),
        )
        .await;
    assert_eq!(outcome, "accepted");
    let (_, list) = setup.web(Method::GET, &path, &setup.lehrer1, None).await;
    assert!(student(&list, "stillerBach").is_none());
    assert!(student(&list, "klugeEule").is_some());

    // The note is kept, and only the school administration sees it.
    let (status, _) = setup
        .web(Method::GET, "/api/web/v1/removals", &setup.lehrer1, None)
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, notes) = setup
        .web(Method::GET, "/api/web/v1/removals", &setup.leitung, None)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        notes,
        json!({ "removals": [{ "time": 500, "account": "stillerBach", "group": "7b",
            "by": "lehrer1" }] })
    );
}

#[tokio::test]
async fn only_the_school_administration_deletes_a_used_account() {
    let setup = Setup::new().await;
    let (status, error) = setup.order(&setup.lehrer1, "klugeEule").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(error["code"], "forbidden");

    let (status, list) = setup.order(&setup.leitung, "klugeEule").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(student(&list, "klugeEule").unwrap()["removal"], "pending");
    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(jobs["jobs"][0]["payload"]["only_unused"], false);

    // The world refuses: the reason stands at the account.
    let job = jobs["jobs"][0]["id"].as_str().unwrap();
    setup
        .world(
            Method::POST,
            &format!("/api/world/v1/jobs/{job}/result"),
            Some(json!({ "ok": false, "message": "incomplete" })),
        )
        .await;
    let path = format!("/api/web/v1/groups/{}/students", setup.first);
    let (_, list) = setup.web(Method::GET, &path, &setup.leitung, None).await;
    let shown = student(&list, "klugeEule").unwrap();
    assert_eq!(shown["removal"], "refused");
    assert_eq!(shown["removal_refusal"], "incomplete");
}

#[tokio::test]
async fn needs_the_account_name_and_a_group_of_ones_own() {
    let setup = Setup::new().await;
    let path = setup.removal(&setup.first, "stillerBach");
    for body in [
        json!({ "confirm": "stillerbach" }),
        json!({ "confirm": "" }),
    ] {
        let (status, error) = setup
            .web(Method::POST, &path, &setup.lehrer1, Some(body))
            .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(error["code"], "invalid_request");
    }
    let (status, _) = setup.web(Method::POST, &path, &setup.lehrer1, None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // Not a teacher of the group, an account of another group, nobody.
    let (status, _) = setup.order(&setup.lehrer2, "stillerBach").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = setup.order(&setup.leitung, "froherWal").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let other = setup.removal(&setup.second, "froherWal");
    let (status, _) = setup
        .web(
            Method::POST,
            &other,
            &setup.lehrer1,
            Some(json!({ "confirm": "froherWal" })),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = setup
        .call(
            Method::POST,
            &path,
            None,
            Some(json!({ "confirm": "stillerBach" })),
        )
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(jobs["jobs"], json!([]));
}

#[tokio::test]
async fn an_order_that_waits_can_be_taken_back() {
    let setup = Setup::new().await;
    let path = setup.removal(&setup.first, "stillerBach");
    let (status, _) = setup.web(Method::DELETE, &path, &setup.lehrer1, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    setup.order(&setup.lehrer1, "stillerBach").await;
    let (status, list) = setup.web(Method::DELETE, &path, &setup.lehrer1, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(student(&list, "stillerBach")
        .unwrap()
        .get("removal")
        .is_none());
    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(jobs["jobs"], json!([]));
}

#[tokio::test]
async fn the_world_says_which_accounts_are_used_and_which_it_deleted_itself() {
    let setup = Setup::new().await;
    let outcome = setup
        .event("e1", "account_used", json!({ "account": "stillerBach" }))
        .await;
    assert_eq!(outcome, "accepted");
    let path = format!("/api/web/v1/groups/{}/students", setup.first);
    let (_, list) = setup.web(Method::GET, &path, &setup.lehrer1, None).await;
    assert_eq!(student(&list, "stillerBach").unwrap()["used"], true);

    // Deleted in the world without an order: the copies go all the same.
    let outcome = setup
        .event("e2", "account_removed", json!({ "account": "stillerBach" }))
        .await;
    assert_eq!(outcome, "accepted");
    let (_, list) = setup.web(Method::GET, &path, &setup.lehrer1, None).await;
    assert!(student(&list, "stillerBach").is_none());
    let (_, notes) = setup
        .web(Method::GET, "/api/web/v1/removals", &setup.leitung, None)
        .await;
    assert_eq!(notes["removals"][0]["account"], "stillerBach");
    assert!(notes["removals"][0].get("by").is_none());

    let outcome = setup
        .event("e3", "account_removed", json!({ "account": "not a name" }))
        .await;
    assert_eq!(outcome, "invalid");
}
