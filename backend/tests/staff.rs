//! Accounts of teachers, looked after by the school administration
//! through the interface for the browser. Called without a network.

use axum::body::Body;
use axum::http::{header, HeaderMap, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::mail::Mailer;
use lep_backend::{clock, db, groups, jobs, logins, teachers, worlds};
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

const STAFF: &str = "/api/web/v1/staff";

impl Setup {
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

    async fn staff(&self) -> Value {
        let (status, json) = self.web(Method::GET, STAFF, &self.leitung, None).await;
        assert_eq!(status, StatusCode::OK);
        json
    }

    /// The jobs of one kind that wait, per world, as payloads.
    async fn waiting(&self, kind: &str) -> Vec<(String, Value)> {
        let mut found = Vec::new();
        for world in [&self.first, &self.second] {
            for job in jobs::take_waiting(&self.state.db, world).await.unwrap() {
                if job.kind == kind {
                    found.push((world.clone(), job.payload));
                }
            }
        }
        found
    }
}

fn entry<'a>(list: &'a Value, account: &str) -> Option<&'a Value> {
    list["staff"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["account"] == account)
}

#[tokio::test]
async fn the_school_administration_creates_a_teacher_in_every_world() {
    let setup = Setup::new().await;
    let (status, slips) = setup
        .web(
            Method::POST,
            STAFF,
            &setup.leitung,
            Some(json!({ "name": " frau_meier " })),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(slips["slips"][0]["account"], "frau_meier");
    let password = slips["slips"][0]["password"].as_str().unwrap();
    // Longer than the one of a student: four words and four digits.
    assert_eq!(password.split('-').count(), 9, "{password}");

    let orders = setup.waiting("create_accounts").await;
    assert_eq!(orders.len(), 2, "one per world");
    // The worlds never see the password: they get what the engine
    // stores of it, the same in every world.
    let stored = orders[0].1["accounts"][0]["entry"].as_str().unwrap();
    assert!(stored.starts_with("#1#"), "{stored}");
    assert!(!orders[0].1.to_string().contains(password));
    for (_, payload) in &orders {
        assert_eq!(
            payload,
            &json!({ "accounts": [{ "name": "frau_meier", "entry": stored }],
                "teacher": true, "by": "leitung" })
        );
    }
    let list = setup.staff().await;
    let shown = entry(&list, "frau_meier").unwrap();
    assert_eq!(shown["state"], "creating");
    assert_eq!(shown["holder"], false);
    assert_eq!(shown["web_access"], "none");

    // The world has created it and reports it as a teacher.
    setup
        .event(
            "e1",
            "accounts_created",
            json!({ "created": ["frau_meier"], "refused": [] }),
        )
        .await;
    setup
        .event(
            "e2",
            "teachers",
            json!({ "accounts": ["leitung", "lehrer1", "lehrer2", "frau_meier"],
                "school_admins": ["leitung"] }),
        )
        .await;
    let list = setup.staff().await;
    let shown = entry(&list, "frau_meier").unwrap();
    assert_eq!(shown["state"], "active");
    assert_eq!(shown["holder"], true);
    // The ones the admin made in the game are listed as well.
    assert_eq!(entry(&list, "lehrer1").unwrap()["groups"], json!(["7b"]));
    assert!(entry(&list, "lehrer1").unwrap().get("state").is_none());
    assert_eq!(entry(&list, "leitung").unwrap()["school_admin"], true);
    assert_eq!(entry(&list, "leitung").unwrap()["web_access"], "confirmed");

    // A new start password goes out the same way, as the next version.
    let (status, slips) = setup
        .web(
            Method::POST,
            &format!("{STAFF}/frau_meier/password"),
            &setup.leitung,
            None,
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    let password = slips["slips"][0]["password"].as_str().unwrap();
    assert!(setup.waiting("set_password").await.is_empty());
    let orders = setup.waiting("set_password_entry").await;
    assert_eq!(orders.len(), 2, "one per world");
    let renewed = orders[0].1["entry"].as_str().unwrap();
    assert_ne!(renewed, stored);
    for (_, payload) in &orders {
        assert_eq!(
            payload,
            &json!({ "name": "frau_meier", "entry": renewed, "by": "leitung" })
        );
        assert!(!payload.to_string().contains(password));
    }
    let list = setup.staff().await;
    assert_eq!(entry(&list, "frau_meier").unwrap()["password"], "pending");

    // A second new password before a world fetched the first: only the
    // newer one is left to fetch.
    for world in [&setup.first, &setup.second] {
        sqlx::query("UPDATE jobs SET delivered_at = NULL WHERE world_id = ?")
            .bind(world)
            .execute(&setup.state.db)
            .await
            .unwrap();
    }
    setup
        .web(
            Method::POST,
            &format!("{STAFF}/frau_meier/password"),
            &setup.leitung,
            None,
        )
        .await;
    let orders = setup.waiting("set_password_entry").await;
    assert_eq!(orders.len(), 2, "one per world");
    assert_ne!(orders[0].1["entry"], renewed);

    // A world that is created later gets the teacher with the password
    // that counts now, and nothing about an account that was refused.
    sqlx::query(
        "INSERT INTO staff_accounts (account, state, created_at, created_by, password_entry)
         VALUES ('herr_alt', 'refused', 0, 'leitung', '#1#YQ#Yg')",
    )
    .execute(&setup.state.db)
    .await
    .unwrap();
    let (third, _) = lep_backend::worlds::add(&setup.state.db, "9c")
        .await
        .unwrap();
    let orders = jobs::take_waiting(&setup.state.db, &third.id)
        .await
        .unwrap();
    assert_eq!(orders.len(), 1);
    assert_eq!(orders[0].kind, "create_accounts");
    assert_eq!(
        orders[0].payload,
        json!({ "accounts": [{ "name": "frau_meier", "entry": orders_entry(&setup).await }],
            "teacher": true, "by": "leitung" })
    );

    // Not a teacher who is being deleted.
    setup
        .web(
            Method::POST,
            &format!("{STAFF}/frau_meier/removal"),
            &setup.leitung,
            Some(json!({ "confirm": "frau_meier" })),
        )
        .await;
    let (fourth, _) = lep_backend::worlds::add(&setup.state.db, "9d")
        .await
        .unwrap();
    let orders = jobs::take_waiting(&setup.state.db, &fourth.id)
        .await
        .unwrap();
    assert!(orders.iter().all(|job| job.kind != "create_accounts"));
}

/// What the backend keeps of the password of "frau_meier".
async fn orders_entry(setup: &Setup) -> String {
    sqlx::query_scalar("SELECT password_entry FROM staff_accounts WHERE account = 'frau_meier'")
        .fetch_one(&setup.state.db)
        .await
        .unwrap()
}

#[tokio::test]
async fn a_name_has_to_be_free_and_fit() {
    let setup = Setup::new().await;
    sqlx::query(
        "INSERT INTO account_removals (time, account, world_id, group_name)
         VALUES (1, 'alterHase', 'x', '7b')",
    )
    .execute(&setup.state.db)
    .await
    .unwrap();
    for name in ["x", "frau meier", "ein_viel_zu_langer_name", "müller", ""] {
        let (status, error) = setup
            .web(
                Method::POST,
                STAFF,
                &setup.leitung,
                Some(json!({ "name": name })),
            )
            .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{name}");
        assert_eq!(error["code"], "invalid_request");
    }
    // A student, a teacher, in another letter case, and a deleted name.
    for name in ["klugeEule", "LEHRER1", "alterhase"] {
        let (status, error) = setup
            .web(
                Method::POST,
                STAFF,
                &setup.leitung,
                Some(json!({ "name": name })),
            )
            .await;
        assert_eq!(status, StatusCode::CONFLICT, "{name}");
        assert_eq!(error["code"], "account_taken");
    }
    assert!(setup.waiting("create_accounts").await.is_empty());

    // The same name twice.
    let create = Some(json!({ "name": "herr_k" }));
    let (status, _) = setup
        .web(Method::POST, STAFF, &setup.leitung, create.clone())
        .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = setup.web(Method::POST, STAFF, &setup.leitung, create).await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn only_the_school_administration_looks_after_teachers() {
    let setup = Setup::new().await;
    let calls = [
        (Method::GET, STAFF.to_owned(), None),
        (
            Method::POST,
            STAFF.to_owned(),
            Some(json!({ "name": "herr_k" })),
        ),
        (Method::POST, format!("{STAFF}/lehrer2/password"), None),
        (
            Method::POST,
            format!("{STAFF}/lehrer2/removal"),
            Some(json!({ "confirm": "lehrer2" })),
        ),
    ];
    for (method, path, body) in calls {
        let (status, error) = setup
            .web(method.clone(), &path, &setup.lehrer1, body.clone())
            .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{method} {path}");
        assert_eq!(error["code"], "forbidden");
        let (status, _, _) = setup.call(method, &path, None, body).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }
    assert!(setup.waiting("create_accounts").await.is_empty());
    assert!(setup.waiting("set_password").await.is_empty());
    assert!(setup.waiting("remove_account").await.is_empty());
}

#[tokio::test]
async fn a_teacher_gets_a_new_password_but_never_the_school_administration() {
    let setup = Setup::new().await;
    let (status, slips) = setup
        .web(
            Method::POST,
            &format!("{STAFF}/lehrer1/password"),
            &setup.leitung,
            None,
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    let password = slips["slips"][0]["password"].as_str().unwrap();
    let orders = setup.waiting("set_password").await;
    assert_eq!(orders.len(), 2);
    assert_eq!(
        orders[0].1,
        json!({ "name": "lehrer1", "password": password, "staff": true, "by": "leitung" })
    );
    let list = setup.staff().await;
    assert_eq!(entry(&list, "lehrer1").unwrap()["password"], "pending");

    // One world does it, the other does not know the account: done.
    let answer = |ok: bool, message: &str| lep_protocol::world::JobResult {
        ok,
        message: message.to_owned(),
    };
    for (index, world) in [&setup.first, &setup.second].into_iter().enumerate() {
        let job = jobs::take_waiting(&setup.state.db, world)
            .await
            .unwrap()
            .remove(0);
        let result = if index == 0 {
            answer(true, "set")
        } else {
            answer(false, "unknown")
        };
        jobs::finish(&setup.state.db, world, &job.id, &result)
            .await
            .unwrap();
    }
    let list = setup.staff().await;
    assert!(entry(&list, "lehrer1").unwrap().get("password").is_none());

    // The school administration, also the own account, and nobody.
    for (account, expected) in [
        ("leitung", StatusCode::FORBIDDEN),
        ("niemand", StatusCode::NOT_FOUND),
        ("klugeEule", StatusCode::NOT_FOUND),
    ] {
        let (status, _) = setup
            .web(
                Method::POST,
                &format!("{STAFF}/{account}/password"),
                &setup.leitung,
                None,
            )
            .await;
        assert_eq!(status, expected, "{account}");
    }
    assert!(setup.waiting("set_password").await.is_empty());
}

#[tokio::test]
async fn deleting_a_teacher_takes_address_access_and_groups_along() {
    let setup = Setup::new().await;
    let path = format!("{STAFF}/lehrer1/removal");
    let (status, _) = setup
        .web(
            Method::POST,
            &path,
            &setup.leitung,
            Some(json!({ "confirm": "Lehrer1" })),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = setup
        .web(
            Method::POST,
            &format!("{STAFF}/leitung/removal"),
            &setup.leitung,
            Some(json!({ "confirm": "leitung" })),
        )
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, list) = setup
        .web(
            Method::POST,
            &path,
            &setup.leitung,
            Some(json!({ "confirm": "lehrer1" })),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(entry(&list, "lehrer1").unwrap()["removal"], "pending");
    let orders = setup.waiting("remove_account").await;
    assert_eq!(orders.len(), 2);
    assert_eq!(
        orders[0].1,
        json!({ "account": "lehrer1", "only_unused": false, "staff": true, "by": "leitung" })
    );
    // Ordering it again adds nothing.
    setup
        .web(
            Method::POST,
            &path,
            &setup.leitung,
            Some(json!({ "confirm": "lehrer1" })),
        )
        .await;
    assert_eq!(setup.waiting("remove_account").await.len(), 2);

    // The teacher is still logged in until a world has deleted.
    let (status, _) = setup
        .web(Method::GET, "/api/web/v1/me", &setup.lehrer1, None)
        .await;
    assert_eq!(status, StatusCode::OK);
    let outcome = setup
        .event(
            "e1",
            "account_removed",
            json!({ "account": "lehrer1", "by": "leitung" }),
        )
        .await;
    assert_eq!(outcome, "accepted");

    let (status, _) = setup
        .web(Method::GET, "/api/web/v1/me", &setup.lehrer1, None)
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let list = setup.staff().await;
    assert!(entry(&list, "lehrer1").is_none());
    let (_, group) = setup
        .web(
            Method::GET,
            &format!("/api/web/v1/groups/{}", setup.first),
            &setup.leitung,
            None,
        )
        .await;
    assert_eq!(group["teachers"], json!([]));
    let (_, notes) = setup
        .web(Method::GET, "/api/web/v1/removals", &setup.leitung, None)
        .await;
    assert_eq!(notes["removals"][0]["account"], "lehrer1");
    // The name is never given out again.
    let (status, _) = setup
        .web(
            Method::POST,
            STAFF,
            &setup.leitung,
            Some(json!({ "name": "lehrer1" })),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn a_student_never_counts_as_a_teacher() {
    let setup = Setup::new().await;
    // Somebody handed out the privileges in the game.
    setup
        .event(
            "e1",
            "teachers",
            json!({ "accounts": ["leitung", "lehrer1", "lehrer2", "klugeEule"],
                "school_admins": ["leitung", "klugeEule"] }),
        )
        .await;
    let list = setup.staff().await;
    assert!(entry(&list, "klugeEule").is_none());
    let (_, teachers) = setup
        .web(Method::GET, "/api/web/v1/teachers", &setup.leitung, None)
        .await;
    assert_eq!(
        teachers["teachers"],
        json!(["lehrer1", "lehrer2", "leitung"])
    );
    let change = json!({ "teachers": ["klugeEule"] });
    let (status, _) = setup
        .web(
            Method::PATCH,
            &format!("/api/web/v1/groups/{}", setup.first),
            &setup.leitung,
            Some(change),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn who_is_a_teacher_nowhere_any_more_loses_the_groups() {
    let setup = Setup::new().await;
    setup
        .event(
            "e1",
            "teachers",
            json!({ "accounts": ["leitung", "lehrer2"], "school_admins": ["leitung"] }),
        )
        .await;
    let (_, group) = setup
        .web(
            Method::GET,
            &format!("/api/web/v1/groups/{}", setup.first),
            &setup.leitung,
            None,
        )
        .await;
    assert_eq!(group["teachers"], json!([]));
    // Another teacher can be assigned now: nothing stale is in the way.
    let (status, _) = setup
        .web(
            Method::PATCH,
            &format!("/api/web/v1/groups/{}", setup.first),
            &setup.leitung,
            Some(json!({ "teachers": ["lehrer2"] })),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
}
