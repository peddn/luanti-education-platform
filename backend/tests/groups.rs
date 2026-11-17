//! Groups in the interface for the browser: who sees what and who may
//! change it. Called without a network.

use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::{clock, db, groups, logins, teachers, worlds};
use lep_protocol::world::{WebAccessAction, WebAccessRequest};
use serde_json::{json, Value};
use sqlx::SqlitePool;
use tower::ServiceExt;

struct Setup {
    state: AppState,
    first: String,
    second: String,
}

/// Gives an account a confirmed address and returns a session token.
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
    /// Two groups, "7b" and "8a". "leitung" is school administration,
    /// "lehrer1" and "lehrer2" are teachers.
    async fn new() -> Self {
        let pool = db::open_in_memory().await.unwrap();
        let (first, _) = worlds::add(&pool, "7b").await.unwrap();
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
        Self {
            state: AppState::new(pool),
            first: first.id,
            second: second.id,
        }
    }

    async fn call(
        &self,
        method: Method,
        path: &str,
        session: Option<&str>,
        body: Option<Value>,
    ) -> (StatusCode, Value) {
        let mut request = Request::builder().method(method).uri(path);
        if let Some(token) = session {
            request = request.header(header::COOKIE, format!("lep_session={token}"));
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

    async fn get(&self, path: &str, session: &str) -> (StatusCode, Value) {
        self.call(Method::GET, path, Some(session), None).await
    }

    async fn patch(&self, id: &str, session: &str, body: Value) -> (StatusCode, Value) {
        let path = format!("/api/web/v1/groups/{id}");
        self.call(Method::PATCH, &path, Some(session), Some(body))
            .await
    }

    /// Returns the names of the groups a session sees.
    async fn group_names(&self, session: &str) -> Vec<String> {
        let (status, json) = self.get("/api/web/v1/groups", session).await;
        assert_eq!(status, StatusCode::OK);
        json["groups"]
            .as_array()
            .unwrap()
            .iter()
            .map(|group| group["name"].as_str().unwrap().to_owned())
            .collect()
    }
}

#[tokio::test]
async fn the_administration_assigns_teachers_and_they_see_their_groups() {
    let setup = Setup::new().await;
    let admin = log_in(&setup.state.db, "leitung").await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;

    let (_, me) = setup.get("/api/web/v1/me", &admin).await;
    assert_eq!(me["school_admin"], true);
    let (_, me) = setup.get("/api/web/v1/me", &teacher).await;
    assert_eq!(me["school_admin"], false);

    assert_eq!(setup.group_names(&admin).await, ["7b", "8a"]);
    assert!(setup.group_names(&teacher).await.is_empty());

    let (status, json) = setup.get("/api/web/v1/teachers", &admin).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["teachers"], json!(["lehrer1", "lehrer2", "leitung"]));

    let (status, json) = setup
        .patch(
            &setup.second,
            &admin,
            json!({ "teachers": ["lehrer2", "lehrer1"] }),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["name"], "8a");
    assert_eq!(json["teachers"], json!(["lehrer1", "lehrer2"]));
    assert!(json.get("last_seen_at").is_none());

    assert_eq!(setup.group_names(&teacher).await, ["8a"]);
    let path = format!("/api/web/v1/groups/{}", setup.second);
    let (status, json) = setup.get(&path, &teacher).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["id"], setup.second.as_str());

    // Renaming and assigning in one request.
    let both = json!({ "name": "Klasse 8a", "teachers": [] });
    let (status, json) = setup.patch(&setup.second, &admin, both).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["name"], "Klasse 8a");
    assert_eq!(json["teachers"], json!([]));
    assert!(setup.group_names(&teacher).await.is_empty());
}

#[tokio::test]
async fn a_teacher_cannot_change_groups_or_look_at_foreign_ones() {
    let setup = Setup::new().await;
    let admin = log_in(&setup.state.db, "leitung").await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    setup
        .patch(&setup.first, &admin, json!({ "teachers": ["lehrer1"] }))
        .await;

    // Not even the own group.
    for id in [&setup.first, &setup.second] {
        for body in [
            json!({ "name": "meins" }),
            json!({ "teachers": ["lehrer1"] }),
        ] {
            let (status, json) = setup.patch(id, &teacher, body).await;
            assert_eq!(status, StatusCode::FORBIDDEN);
            assert_eq!(json["code"], "forbidden");
        }
    }
    assert_eq!(setup.group_names(&admin).await, ["7b", "8a"]);

    let (status, json) = setup.get("/api/web/v1/teachers", &teacher).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(json["code"], "forbidden");

    // A foreign group does not exist for the teacher.
    let path = format!("/api/web/v1/groups/{}", setup.second);
    let (status, json) = setup.get(&path, &teacher).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(json["code"], "not_found");
}

#[tokio::test]
async fn nothing_works_without_a_login() {
    let setup = Setup::new().await;
    let group = format!("/api/web/v1/groups/{}", setup.first);
    for (method, path) in [
        (Method::GET, "/api/web/v1/groups"),
        (Method::GET, group.as_str()),
        (Method::PATCH, group.as_str()),
        (Method::GET, "/api/web/v1/teachers"),
    ] {
        let body = (method == Method::PATCH).then(|| json!({ "name": "x" }));
        let (status, json) = setup.call(method, path, None, body).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{path}");
        assert_eq!(json["code"], "unauthorized");
    }
}

#[tokio::test]
async fn changes_that_cannot_be_made_get_a_code() {
    let setup = Setup::new().await;
    let admin = log_in(&setup.state.db, "leitung").await;
    let cases = [
        (json!({ "name": "8A" }), StatusCode::CONFLICT, "name_taken"),
        (
            json!({ "name": "  " }),
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
        (
            json!({ "teachers": ["schueler1"] }),
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
        (
            json!({ "teachers": "lehrer1" }),
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
    ];
    for (body, expected, code) in cases {
        let (status, json) = setup.patch(&setup.first, &admin, body.clone()).await;
        assert_eq!(status, expected, "{body}");
        assert_eq!(json["code"], code);
    }
    let (status, json) = setup
        .patch("no-such-id", &admin, json!({ "name": "9c" }))
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(json["code"], "not_found");
    assert_eq!(setup.group_names(&admin).await, ["7b", "8a"]);
}

#[tokio::test]
async fn the_world_takes_the_role_away_at_once() {
    let setup = Setup::new().await;
    let admin = log_in(&setup.state.db, "leitung").await;
    groups::set_school_admins(&setup.state.db, &setup.first, &[])
        .await
        .unwrap();
    let (status, _) = setup
        .patch(&setup.first, &admin, json!({ "name": "9c" }))
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert!(setup.group_names(&admin).await.is_empty());
}
