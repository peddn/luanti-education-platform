//! Accounts of students in the interface for the browser and on their
//! way into the world. Called without a network.

use axum::body::Body;
use axum::http::{header, HeaderMap, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::{clock, db, groups, logins, teachers, worlds};
use lep_protocol::web::GroupChange;
use lep_protocol::world::{WebAccessAction, WebAccessRequest};
use serde_json::{json, Value};
use sqlx::{Row, SqlitePool};
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
            state: AppState::new(pool),
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

    fn students(&self, group: &str) -> String {
        format!("/api/web/v1/groups/{group}/students")
    }

    /// Returns account names and states of a group as the session sees
    /// them.
    async fn listed(&self, group: &str, session: &str) -> Vec<(String, String)> {
        let (status, json) = self
            .web(Method::GET, &self.students(group), session, None)
            .await;
        assert_eq!(status, StatusCode::OK);
        pairs(&json)
    }
}

fn pairs(json: &Value) -> Vec<(String, String)> {
    json["students"]
        .as_array()
        .unwrap()
        .iter()
        .map(|student| {
            (
                student["account"].as_str().unwrap().to_owned(),
                student["state"].as_str().unwrap().to_owned(),
            )
        })
        .collect()
}

#[tokio::test]
async fn a_teacher_rolls_names_and_the_world_creates_the_accounts() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let path = setup.students(&setup.first);
    assert!(setup.listed(&setup.first, &teacher).await.is_empty());

    // Three names, one rolled again, one removed.
    let (status, json) = setup
        .web(Method::POST, &path, &teacher, Some(json!({ "count": 3 })))
        .await;
    assert_eq!(status, StatusCode::OK);
    let drafted = pairs(&json);
    assert_eq!(drafted.len(), 3);
    assert!(drafted.iter().all(|(_, state)| state == "draft"));

    let reroll = format!("{path}/{}/reroll", drafted[0].0);
    let (status, json) = setup.web(Method::POST, &reroll, &teacher, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(!pairs(&json).iter().any(|(name, _)| *name == drafted[0].0));
    let remove = format!("{path}/{}", drafted[1].0);
    let (status, json) = setup.web(Method::DELETE, &remove, &teacher, None).await;
    assert_eq!(status, StatusCode::OK);
    let kept: Vec<String> = pairs(&json).into_iter().map(|(name, _)| name).collect();
    assert_eq!(kept.len(), 2);

    // Creating shows the passwords once and must not be cached.
    let cookie = (header::COOKIE, format!("lep_session={teacher}"));
    let (status, json, headers) = setup
        .call(Method::POST, &format!("{path}/create"), Some(cookie), None)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers.get(header::CACHE_CONTROL).unwrap(), "no-store");
    let slips = json["slips"].as_array().unwrap();
    assert_eq!(slips.len(), 2);
    for slip in slips {
        assert!(kept.contains(&slip["account"].as_str().unwrap().to_owned()));
        assert_eq!(slip["password"].as_str().unwrap().split('-').count(), 3);
    }
    assert!(setup
        .listed(&setup.first, &teacher)
        .await
        .iter()
        .all(|(_, state)| state == "creating"));

    // The world fetches the job with the same names and passwords.
    let (status, json) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(status, StatusCode::OK);
    let job = &json["jobs"][0];
    assert_eq!(job["kind"], "create_accounts");
    let ordered = job["payload"]["accounts"].as_array().unwrap();
    for (account, slip) in ordered.iter().zip(slips) {
        assert_eq!(account["name"], slip["account"]);
        assert_eq!(account["password"], slip["password"]);
    }

    // It reports what it did, then that the job is done.
    let report = json!({ "events": [{
        "id": "e1", "kind": "accounts_created", "time": 1700000000,
        "payload": { "created": [kept[0]], "refused": [kept[1]] }
    }] });
    let (_, answer) = setup
        .world(Method::POST, "/api/world/v1/events", Some(report))
        .await;
    assert_eq!(answer["results"][0]["outcome"], "accepted");
    let result = format!("/api/world/v1/jobs/{}/result", job["id"].as_str().unwrap());
    let done = json!({ "ok": true, "message": "1 created, 1 refused" });
    assert_eq!(
        setup.world(Method::POST, &result, Some(done)).await.0,
        StatusCode::OK
    );

    let now = setup.listed(&setup.first, &teacher).await;
    assert!(now.contains(&(kept[0].clone(), "active".to_owned())));
    assert!(now.contains(&(kept[1].clone(), "refused".to_owned())));

    // The passwords are gone from the database.
    let stored: String = sqlx::query("SELECT payload FROM jobs WHERE kind = 'create_accounts'")
        .fetch_one(&setup.state.db)
        .await
        .unwrap()
        .get("payload");
    assert_eq!(stored, "{}");
    for slip in slips {
        assert!(!stored.contains(slip["password"].as_str().unwrap()));
    }

    // Nothing left to create.
    let (status, json) = setup
        .web(Method::POST, &format!("{path}/create"), &teacher, None)
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["code"], "invalid_request");
}

#[tokio::test]
async fn a_teacher_orders_a_new_password_for_a_student() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let stranger = log_in(&setup.state.db, "lehrer2").await;
    let path = setup.students(&setup.first);

    // One account that exists in the world.
    setup
        .web(Method::POST, &path, &teacher, Some(json!({ "count": 1 })))
        .await;
    setup
        .web(Method::POST, &format!("{path}/create"), &teacher, None)
        .await;
    let name = setup.listed(&setup.first, &teacher).await.remove(0).0;
    let reset = format!("{path}/{name}/password");

    // Not before the world has created it.
    let (status, json) = setup.web(Method::POST, &reset, &teacher, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(json["code"], "not_found");

    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    let created = json!({ "events": [{
        "id": "e1", "kind": "accounts_created", "time": 1700000000,
        "payload": { "created": [name] }
    }] });
    setup
        .world(Method::POST, "/api/world/v1/events", Some(created))
        .await;
    let done = format!(
        "/api/world/v1/jobs/{}/result",
        jobs["jobs"][0]["id"].as_str().unwrap()
    );
    setup
        .world(
            Method::POST,
            &done,
            Some(json!({ "ok": true, "message": "1 created" })),
        )
        .await;

    // Nobody from outside the group, and nobody without a login.
    let (status, _) = setup.web(Method::POST, &reset, &stranger, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = setup.call(Method::POST, &reset, None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // The teacher gets one slip, once, not to be cached.
    let cookie = (header::COOKIE, format!("lep_session={teacher}"));
    let (status, json, headers) = setup.call(Method::POST, &reset, Some(cookie), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers.get(header::CACHE_CONTROL).unwrap(), "no-store");
    let slips = json["slips"].as_array().unwrap();
    assert_eq!(slips.len(), 1);
    assert_eq!(slips[0]["account"], name.as_str());
    let password = slips[0]["password"].as_str().unwrap().to_owned();

    let (_, list) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(list["students"][0]["password"], "pending");

    // The world gets the order and refuses it: the list says so.
    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    let job = &jobs["jobs"][0];
    assert_eq!(job["kind"], "set_password");
    assert_eq!(
        job["payload"],
        json!({ "name": name, "password": password })
    );
    let result = format!("/api/world/v1/jobs/{}/result", job["id"].as_str().unwrap());
    setup
        .world(
            Method::POST,
            &result,
            Some(json!({ "ok": false, "message": "staff" })),
        )
        .await;
    let (_, list) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(list["students"][0]["password"], "refused");

    // A second order, done this time: nothing left to show, and no
    // password left in the database.
    setup.web(Method::POST, &reset, &teacher, None).await;
    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    let result = format!(
        "/api/world/v1/jobs/{}/result",
        jobs["jobs"][0]["id"].as_str().unwrap()
    );
    setup
        .world(
            Method::POST,
            &result,
            Some(json!({ "ok": true, "message": "set" })),
        )
        .await;
    let (_, list) = setup.web(Method::GET, &path, &teacher, None).await;
    assert!(list["students"][0].get("password").is_none());
    let payloads: Vec<String> = sqlx::query("SELECT payload FROM jobs WHERE kind = 'set_password'")
        .fetch_all(&setup.state.db)
        .await
        .unwrap()
        .iter()
        .map(|row| row.get("payload"))
        .collect();
    assert_eq!(payloads, vec!["{}", "{}"]);
}

#[tokio::test]
async fn only_the_teachers_of_a_group_and_the_administration_get_in() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let stranger = log_in(&setup.state.db, "lehrer2").await;
    let admin = log_in(&setup.state.db, "leitung").await;
    let path = setup.students(&setup.first);
    setup
        .web(Method::POST, &path, &teacher, Some(json!({ "count": 2 })))
        .await;
    let name = setup.listed(&setup.first, &teacher).await.remove(0).0;

    // For a teacher of another group this one does not exist.
    let attempts = [
        (Method::GET, path.clone(), None),
        (Method::POST, path.clone(), Some(json!({ "count": 1 }))),
        (Method::POST, format!("{path}/create"), None),
        (Method::POST, format!("{path}/{name}/reroll"), None),
        (Method::DELETE, format!("{path}/{name}"), None),
    ];
    for (method, path, body) in attempts.clone() {
        let (status, json) = setup.web(method, &path, &stranger, body).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{path}");
        assert_eq!(json["code"], "not_found");
    }
    for (method, path, body) in attempts {
        let (status, json, _) = setup.call(method, &path, None, body).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{path}");
        assert_eq!(json["code"], "unauthorized");
    }
    assert_eq!(setup.listed(&setup.first, &teacher).await.len(), 2);

    // The teacher of 7b has no way into 8a, the administration into both.
    let other = setup.students(&setup.second);
    let (status, _) = setup.web(Method::GET, &other, &teacher, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(setup.listed(&setup.first, &admin).await.len(), 2);
    let (status, _) = setup
        .web(Method::POST, &other, &admin, Some(json!({ "count": 1 })))
        .await;
    assert_eq!(status, StatusCode::OK);

    // A name of 8a cannot be changed through 7b.
    let foreign = setup.listed(&setup.second, &admin).await.remove(0).0;
    let (status, _) = setup
        .web(Method::DELETE, &format!("{path}/{foreign}"), &teacher, None)
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(setup.listed(&setup.second, &admin).await.len(), 1);
}

#[tokio::test]
async fn requests_that_make_no_sense_get_a_code() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let path = setup.students(&setup.first);
    for body in [
        json!({ "count": 0 }),
        json!({ "count": 41 }),
        json!({ "count": -1 }),
        json!({}),
    ] {
        let (status, json) = setup
            .web(Method::POST, &path, &teacher, Some(body.clone()))
            .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
        assert_eq!(json["code"], "invalid_request");
    }
    let (status, json) = setup
        .web(
            Method::POST,
            &format!("{path}/niemand/reroll"),
            &teacher,
            None,
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(json["code"], "not_found");
    assert!(setup.listed(&setup.first, &teacher).await.is_empty());
}

#[tokio::test]
async fn the_address_of_the_world_is_for_the_administration_to_set() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let admin = log_in(&setup.state.db, "leitung").await;
    let path = format!("/api/web/v1/groups/{}", setup.first);
    let change = json!({ "address": "spiel.schule.example, Port 30000" });

    let (status, _) = setup
        .web(Method::PATCH, &path, &teacher, Some(change.clone()))
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, json) = setup.web(Method::PATCH, &path, &admin, Some(change)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["address"], "spiel.schule.example, Port 30000");

    // The teacher reads it, for the slips.
    let (_, json) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(json["address"], "spiel.schule.example, Port 30000");
}
