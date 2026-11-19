//! Display names on their way from the world to the browser and to the
//! teachers by mail, and what a teacher orders on its way back. Called
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

impl Setup {
    fn students(&self, group: &str) -> String {
        format!("/api/web/v1/groups/{group}/students")
    }

    /// Sends events as the world of the first group.
    async fn report(&self, events: Value) -> Value {
        let (status, json) = self
            .world(
                Method::POST,
                "/api/world/v1/events",
                Some(json!({ "events": events })),
            )
            .await;
        assert_eq!(status, StatusCode::OK);
        json["results"].clone()
    }

    /// The first group gets a student whose account exists.
    async fn with_a_student(&self) {
        sqlx::query(
            "INSERT INTO students (account, world_id, state, created_at)
             VALUES ('klugeEule', ?, 'active', 0)",
        )
        .bind(&self.first)
        .execute(&self.state.db)
        .await
        .unwrap();
    }

    /// Takes the next job of the world and answers it.
    async fn answer_job(&self, ok: bool) -> Value {
        let (_, jobs) = self
            .world(Method::GET, "/api/world/v1/jobs?wait=0", None)
            .await;
        let job = jobs["jobs"][0].clone();
        let result = format!("/api/world/v1/jobs/{}/result", job["id"].as_str().unwrap());
        self.world(
            Method::POST,
            &result,
            Some(json!({ "ok": ok, "message": "" })),
        )
        .await;
        job
    }
}

fn name_event(id: &str, time: i64, payload: Value) -> Value {
    json!([{ "id": id, "kind": "display_name", "time": time, "payload": payload }])
}

#[tokio::test]
async fn a_new_name_reaches_the_list_and_the_teachers_of_the_group() {
    let setup = Setup::new().await;
    setup.with_a_student().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let path = setup.students(&setup.first);

    let (_, json) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(
        json["students"],
        json!([{ "account": "klugeEule", "state": "active", "display_locked": false, "used": false }])
    );

    let results = setup
        .report(name_event(
            "n1",
            1700000000,
            json!({ "account": "klugeEule", "name": "Lena Maier", "changed_at": 1700000000, "locked": false }),
        ))
        .await;
    assert_eq!(results[0]["outcome"], "accepted");
    let (_, json) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(
        json["students"][0],
        json!({ "account": "klugeEule", "state": "active", "display_name": "Lena Maier",
            "display_changed_at": 1700000000, "display_locked": false, "used": false })
    );
    // The progress of the group names it too.
    let (_, json) = setup
        .web(
            Method::GET,
            &format!("/api/web/v1/groups/{}/progress", setup.first),
            &teacher,
            None,
        )
        .await;
    assert_eq!(json["students"][0]["display_name"], "Lena Maier");

    // One mail, to the teacher of the group, with account and name.
    let mails = setup.state.mailer.kept();
    assert_eq!(mails.len(), 1);
    assert_eq!(mails[0].to, "lehrer1@schule.example");
    assert!(mails[0].body.contains("klugeEule"));
    assert!(mails[0].body.contains("Lena Maier"));

    // The same event again, and the same state under a new id: no mail.
    setup
        .report(name_event(
            "n1",
            1700000000,
            json!({ "account": "klugeEule", "name": "Lena Maier" }),
        ))
        .await;
    setup
        .report(name_event(
            "n2",
            1700000010,
            json!({ "account": "klugeEule", "name": "Lena Maier", "changed_at": 1700000000 }),
        ))
        .await;
    // A name of somebody who is no student of the group: stored, no mail.
    setup
        .report(name_event(
            "n3",
            1700000020,
            json!({ "account": "lehrer1", "name": "Herr Maier" }),
        ))
        .await;
    assert_eq!(setup.state.mailer.kept().len(), 1);

    // A payload that makes no sense is refused.
    let results = setup
        .report(name_event("n4", 1700000030, json!({ "name": "Lena" })))
        .await;
    assert_eq!(results[0]["outcome"], "invalid");
}

#[tokio::test]
async fn a_teacher_takes_a_name_away_and_locks_choosing() {
    let setup = Setup::new().await;
    setup.with_a_student().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let path = setup.students(&setup.first);
    setup
        .report(name_event(
            "n1",
            1700000000,
            json!({ "account": "klugeEule", "name": "Lena Maier", "changed_at": 1700000000 }),
        ))
        .await;

    let name = format!("{path}/klugeEule/display-name");
    let (status, json) = setup.web(Method::DELETE, &name, &teacher, None).await;
    assert_eq!(status, StatusCode::OK);
    // Nothing has changed yet: the world decides.
    assert_eq!(json["students"][0]["display_name"], "Lena Maier");
    assert_eq!(json["students"][0]["display_change"], "pending");

    let job = setup.answer_job(true).await;
    assert_eq!(job["kind"], "remove_display_name");
    assert_eq!(
        job["payload"],
        json!({ "account": "klugeEule", "by": "lehrer1" })
    );
    // The world reports the new state: no name, no mail about that.
    setup
        .report(name_event(
            "n2",
            1700000100,
            json!({ "account": "klugeEule", "name": null, "changed_at": null, "locked": false }),
        ))
        .await;
    let (_, json) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(
        json["students"][0],
        json!({ "account": "klugeEule", "state": "active", "display_locked": false, "used": false })
    );
    assert_eq!(setup.state.mailer.kept().len(), 1);

    let lock = format!("{name}/lock");
    let (status, _) = setup
        .web(
            Method::POST,
            &lock,
            &teacher,
            Some(json!({ "locked": true })),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    let job = setup.answer_job(false).await;
    assert_eq!(job["kind"], "set_display_locked");
    assert_eq!(
        job["payload"],
        json!({ "account": "klugeEule", "locked": true, "by": "lehrer1" })
    );
    let (_, json) = setup.web(Method::GET, &path, &teacher, None).await;
    assert_eq!(json["students"][0]["display_change"], "refused");

    let (status, json) = setup
        .web(
            Method::POST,
            &lock,
            &teacher,
            Some(json!({ "locked": "yes" })),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["code"], "invalid_request");
    let (status, _) = setup
        .web(
            Method::DELETE,
            &format!("{path}/niemand/display-name"),
            &teacher,
            None,
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn the_history_comes_from_the_protocol_of_the_world() {
    let setup = Setup::new().await;
    setup.with_a_student().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let results = setup
        .report(json!([
            { "id": "p1", "kind": "protocol", "time": 1700000000, "payload": {
                "protocol": "names", "account": "klugeEule",
                "fields": { "action": "chosen", "name": "Lena Maier", "by": "klugeEule" } } },
            { "id": "p2", "kind": "protocol", "time": 1700000100, "payload": {
                "protocol": "names", "account": "klugeEule",
                "fields": { "action": "removed", "name": "Lena Maier", "by": "lehrer1" } } }
        ]))
        .await;
    assert_eq!(results[0]["outcome"], "accepted");
    let history = format!("{}/klugeEule/display-names", setup.students(&setup.first));
    let (status, json) = setup.web(Method::GET, &history, &teacher, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        json["entries"],
        json!([
            { "time": 1700000100, "action": "removed", "name": "Lena Maier", "by": "lehrer1" },
            { "time": 1700000000, "action": "chosen", "name": "Lena Maier", "by": "klugeEule" }
        ])
    );
}

#[tokio::test]
async fn only_the_teachers_of_a_group_and_the_administration_get_in() {
    let setup = Setup::new().await;
    setup.with_a_student().await;
    let stranger = log_in(&setup.state.db, "lehrer2").await;
    let administration = log_in(&setup.state.db, "leitung").await;
    let base = format!("{}/klugeEule", setup.students(&setup.first));
    let name = format!("{base}/display-name");
    let lock = format!("{name}/lock");
    let history = format!("{base}/display-names");
    let locked = Some(json!({ "locked": true }));

    for (method, path, body) in [
        (Method::DELETE, &name, None),
        (Method::POST, &lock, locked.clone()),
        (Method::GET, &history, None),
    ] {
        let (status, json) = setup
            .web(method.clone(), path, &stranger, body.clone())
            .await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{path}");
        assert_eq!(json["code"], "not_found");
        let (status, _, _) = setup.call(method, path, None, body).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{path}");
    }
    let (_, jobs) = setup
        .world(Method::GET, "/api/world/v1/jobs?wait=0", None)
        .await;
    assert_eq!(jobs["jobs"], json!([]));

    let (status, _) = setup
        .web(Method::POST, &lock, &administration, locked)
        .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = setup
        .web(Method::GET, &history, &administration, None)
        .await;
    assert_eq!(status, StatusCode::OK);
    // Not through another group.
    let elsewhere = format!("{}/klugeEule/display-name", setup.students(&setup.second));
    let (status, _) = setup
        .web(Method::DELETE, &elsewhere, &administration, None)
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
