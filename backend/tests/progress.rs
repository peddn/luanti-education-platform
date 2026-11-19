//! The progress of students in the interface for the browser, and the
//! changes a teacher orders on their way into the world. Called without
//! a network.

use axum::body::Body;
use axum::http::{header, HeaderMap, Method, Request, StatusCode};
use http_body_util::BodyExt;
use lep_backend::app::{self, AppState};
use lep_backend::{clock, db, groups, logins, teachers, worlds};
use lep_protocol::web::GroupChange;
use lep_protocol::world::{WebAccessAction, WebAccessRequest};
use serde_json::{json, Value};
use sqlx::SqlitePool;
use tower::ServiceExt;

const MATH: &str = "lep_math:math";

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
}

impl Setup {
    fn progress(&self, group: &str) -> String {
        format!("/api/web/v1/groups/{group}/progress")
    }

    /// Sends events as the world of the first group.
    async fn report(&self, events: Value) {
        let (status, json) = self
            .world(
                Method::POST,
                "/api/world/v1/events",
                Some(json!({ "events": events })),
            )
            .await;
        assert_eq!(status, StatusCode::OK);
        for result in json["results"].as_array().unwrap() {
            assert_eq!(result["outcome"], "accepted");
        }
    }

    /// The world has one module with two levels, and the group one
    /// student whose account exists.
    async fn with_a_student(&self) {
        self.report(json!([{
            "id": "m1", "kind": "modules", "time": 1700000000,
            "payload": { "modules": [{ "id": MATH, "title": "Kopfrechnen", "levels": [
                { "stage": false, "tasks": [{ "id": "add", "title": "Addieren", "required": 5 }] },
                { "stage": true, "tasks": [{ "id": "sub", "title": "Subtrahieren", "required": 5 }] }
            ] }] }
        }]))
        .await;
        sqlx::query(
            "INSERT INTO students (account, world_id, state, created_at)
             VALUES ('klugeEule', ?, 'active', 0)",
        )
        .bind(&self.first)
        .execute(&self.state.db)
        .await
        .unwrap();
    }
}

#[tokio::test]
async fn a_teacher_sees_the_progress_and_orders_a_change() {
    let setup = Setup::new().await;
    setup.with_a_student().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let path = setup.progress(&setup.first);

    let (status, json) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        json["modules"],
        json!([{ "id": MATH, "title": "Kopfrechnen", "levels": 2 }])
    );
    assert_eq!(
        json["students"],
        json!([{ "account": "klugeEule", "trophies": [], "modules": [{
            "module": MATH, "started": false, "level": 1, "locked": false, "percent": 0,
            "completed": false,
            "tasks": [{ "title": "Addieren", "solved": 0, "required": 5 }]
        }] }])
    );

    // The id of a module has a colon; it travels in the path.
    let cell = format!("{path}/klugeEule/lep_math%3Amath");
    let (status, json) = setup
        .web(Method::POST, &cell, &teacher, Some(json!({ "level": 2 })))
        .await;
    assert_eq!(status, StatusCode::OK);
    // Nothing has changed yet: the world decides.
    assert_eq!(json["students"][0]["modules"][0]["level"], 1);
    assert_eq!(json["students"][0]["modules"][0]["change"], "pending");

    // The world gets the order with the name of the teacher, does it and
    // reports the new state.
    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    let job = &jobs["jobs"][0];
    assert_eq!(job["kind"], "set_level");
    assert_eq!(
        job["payload"],
        json!({ "account": "klugeEule", "module": MATH, "level": 2, "by": "lehrer1" })
    );
    let result = format!("/api/world/v1/jobs/{}/result", job["id"].as_str().unwrap());
    setup
        .world(
            Method::POST,
            &result,
            Some(json!({ "ok": true, "message": "set" })),
        )
        .await;
    setup
        .report(json!([
            { "id": "p1", "kind": "progress", "time": 1700000100, "payload": {
                "account": "klugeEule", "module": MATH, "level": 2, "locked": false,
                "percent": 40, "completed": false,
                "tasks": [{ "id": "sub", "solved": 2, "required": 5 }] } },
            { "id": "t1", "kind": "trophies", "time": 1700000100, "payload": {
                "account": "klugeEule",
                "trophies": [{ "id": "a", "title": "Rechenpokal", "material": "silver" }] } }
        ]))
        .await;
    let (_, json) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(
        json["students"][0],
        json!({ "account": "klugeEule",
            "trophies": [{ "title": "Rechenpokal", "material": "silver" }],
            "modules": [{
                "module": MATH, "started": true, "level": 2, "locked": false, "percent": 40,
                "completed": false,
                "tasks": [{ "title": "Subtrahieren", "solved": 2, "required": 5 }]
            }] })
    );

    // A lock the world refuses stays visible as refused.
    setup
        .web(
            Method::POST,
            &cell,
            &teacher,
            Some(json!({ "locked": true })),
        )
        .await;
    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(jobs["jobs"][0]["kind"], "set_locked");
    assert_eq!(jobs["jobs"][0]["payload"]["locked"], true);
    let result = format!(
        "/api/world/v1/jobs/{}/result",
        jobs["jobs"][0]["id"].as_str().unwrap()
    );
    setup
        .world(
            Method::POST,
            &result,
            Some(json!({ "ok": false, "message": "unknown" })),
        )
        .await;
    let (_, json) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(json["students"][0]["modules"][0]["change"], "refused");
}

#[tokio::test]
async fn only_the_teachers_of_a_group_and_the_administration_get_in() {
    let setup = Setup::new().await;
    setup.with_a_student().await;
    let stranger = log_in(&setup.state.db, "lehrer2").await;
    let administration = log_in(&setup.state.db, "leitung").await;
    let path = setup.progress(&setup.first);
    let cell = format!("{path}/klugeEule/lep_math%3Amath");
    let level = Some(json!({ "level": 2 }));

    let (status, json) = setup.web(Method::GET, &path, &stranger, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(json["code"], "not_found");
    let (status, _) = setup
        .web(Method::POST, &cell, &stranger, level.clone())
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = setup.call(Method::GET, &path, None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _, _) = setup.call(Method::POST, &cell, None, level.clone()).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // Nothing was ordered so far.
    let (_, jobs) = setup
        .world(Method::GET, "/api/world/v1/jobs?wait=0", None)
        .await;
    assert_eq!(jobs["jobs"], json!([]));

    let (status, _) = setup.web(Method::GET, &path, &administration, None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = setup.web(Method::POST, &cell, &administration, level).await;
    assert_eq!(status, StatusCode::OK);
    // A group without students and modules is an empty table.
    let (status, json) = setup
        .web(
            Method::GET,
            &setup.progress(&setup.second),
            &administration,
            None,
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json, json!({ "modules": [], "students": [] }));
}

#[tokio::test]
async fn changes_that_cannot_be_made_get_a_code() {
    let setup = Setup::new().await;
    setup.with_a_student().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let path = setup.progress(&setup.first);
    let cases = [
        (
            "klugeEule/lep_math%3Amath",
            json!({ "level": 3 }),
            400,
            "invalid_request",
        ),
        (
            "klugeEule/lep_math%3Amath",
            json!({ "level": 0 }),
            400,
            "invalid_request",
        ),
        (
            "klugeEule/lep_math%3Amath",
            json!({}),
            400,
            "invalid_request",
        ),
        (
            "klugeEule/lep_math%3Amath",
            json!({ "level": "two" }),
            400,
            "invalid_request",
        ),
        (
            "klugeEule/lep_tz%3Atz",
            json!({ "level": 1 }),
            404,
            "not_found",
        ),
        (
            "niemand/lep_math%3Amath",
            json!({ "level": 1 }),
            404,
            "not_found",
        ),
    ];
    for (cell, body, status, code) in cases {
        let (got, json) = setup
            .web(
                Method::POST,
                &format!("{path}/{cell}"),
                &teacher,
                Some(body.clone()),
            )
            .await;
        assert_eq!(got.as_u16(), status, "{cell} {body}");
        assert_eq!(json["code"], code, "{cell} {body}");
    }
}

#[tokio::test]
async fn the_progress_can_be_downloaded_and_the_export_is_noted() {
    let setup = Setup::new().await;
    setup.with_a_student().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let stranger = log_in(&setup.state.db, "lehrer2").await;
    let administration = log_in(&setup.state.db, "leitung").await;
    let path = format!("{}/export", setup.progress(&setup.first));

    let (status, _) = setup.web(Method::GET, &path, &stranger, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = setup.call(Method::GET, &path, None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let cookie = (header::COOKIE, format!("lep_session={teacher}"));
    let (status, _, headers) = setup.call(Method::GET, &path, Some(cookie), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers[header::CONTENT_TYPE], "text/csv; charset=utf-8");
    assert_eq!(
        headers[header::CONTENT_DISPOSITION],
        "attachment; filename=\"fortschritt-7b.csv\""
    );
    assert_eq!(headers[header::CACHE_CONTROL], "no-store");

    // Only the one download that worked stands in the list of exports,
    // which the school administration sees.
    let exports = format!("/api/web/v1/groups/{}/protocols/exports", setup.first);
    let (status, page) = setup
        .web(Method::GET, &exports, &administration, None)
        .await;
    assert_eq!(status, StatusCode::OK);
    let entries = page["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0]["account"], "lehrer1");
    assert_eq!(entries[0]["fields"]["protocol"], "progress");
    assert_eq!(entries[0]["fields"]["entries"], "1");
}
