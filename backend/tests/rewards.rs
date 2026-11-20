//! The reward table of a group through the interfaces for the browser
//! and the world. Called without a network.

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

fn table() -> Value {
    json!({
        "task": { "name": "default:steel_ingot", "count": 1 },
        "daily": { "name": "default:gold_ingot", "count": 1 },
        "level": { "name": "default:gold_ingot", "count": 1 },
        "stage": { "name": "default:diamond", "count": 1 },
        "module": { "name": "default:diamond", "count": 3 },
        "daily_limit": 5
    })
}

impl Setup {
    fn rewards(&self, group: &str) -> String {
        format!("/api/web/v1/groups/{group}/rewards")
    }

    /// The world of the first group reports its table.
    async fn report(&self, id: &str, table: Value) -> Value {
        let (status, json) = self
            .world(
                Method::POST,
                "/api/world/v1/events",
                Some(
                    json!({ "events": [{ "id": id, "kind": "rewards", "time": 500,
                    "payload": { "table": table, "choices": [
                        { "name": "default:steel_ingot", "title": "Stahlbarren" },
                        { "name": "default:gold_ingot", "title": "Goldbarren" },
                        { "name": "default:diamond", "title": "Diamant" },
                        { "name": "default:coal_lump", "title": "Kohlestück" }
                    ] } }] }),
                ),
            )
            .await;
        assert_eq!(status, StatusCode::OK);
        json["results"][0]["outcome"].clone()
    }
}

#[tokio::test]
async fn a_teacher_changes_the_table_and_the_world_reports_it() {
    let setup = Setup::new().await;
    let path = setup.rewards(&setup.first);

    // Nothing reported yet: no table, and nothing can be ordered.
    let (status, shown) = setup.web(Method::GET, &path, &setup.lehrer1, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(shown.get("table").is_none());
    assert_eq!(shown["max_count"], 99);
    let (status, _) = setup
        .web(
            Method::PUT,
            &path,
            &setup.lehrer1,
            Some(json!({ "table": table() })),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    assert_eq!(setup.report("e1", table()).await, "accepted");
    let (_, shown) = setup.web(Method::GET, &path, &setup.lehrer1, None).await;
    assert_eq!(shown["table"], table());
    assert_eq!(shown["choices"][3]["title"], "Kohlestück");

    let mut wanted = table();
    wanted["task"] = json!({ "name": "default:coal_lump", "count": 4 });
    wanted["daily_limit"] = json!(0);
    let (status, shown) = setup
        .web(
            Method::PUT,
            &path,
            &setup.lehrer1,
            Some(json!({ "table": wanted })),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        shown["table"],
        table(),
        "the old one counts until the world reports"
    );
    assert_eq!(shown["change"], "pending");

    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(jobs["jobs"][0]["kind"], "set_rewards");
    assert_eq!(
        jobs["jobs"][0]["payload"],
        json!({ "table": wanted, "by": "lehrer1" })
    );
    let job = jobs["jobs"][0]["id"].as_str().unwrap();
    setup
        .world(
            Method::POST,
            &format!("/api/world/v1/jobs/{job}/result"),
            Some(json!({ "ok": true, "message": "set" })),
        )
        .await;
    assert_eq!(setup.report("e2", wanted.clone()).await, "accepted");
    let (_, shown) = setup.web(Method::GET, &path, &setup.lehrer1, None).await;
    assert_eq!(shown["table"], wanted);
    assert!(shown.get("change").is_none());

    // The default comes back without a table.
    let (status, _) = setup
        .web(Method::PUT, &path, &setup.leitung, Some(json!({})))
        .await;
    assert_eq!(status, StatusCode::OK);
    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(jobs["jobs"][0]["payload"], json!({ "by": "leitung" }));

    // Every group has its own table: the other world reported nothing.
    let other = setup.rewards(&setup.second);
    let (status, shown) = setup.web(Method::GET, &other, &setup.leitung, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(shown.get("table").is_none());
}

#[tokio::test]
async fn refuses_what_cannot_be_and_who_has_no_business() {
    let setup = Setup::new().await;
    let path = setup.rewards(&setup.first);
    setup.report("e1", table()).await;

    let mut cases = Vec::new();
    let mut wanted = table();
    wanted["task"]["name"] = json!("default:mese");
    cases.push(wanted);
    let mut wanted = table();
    wanted["stage"]["count"] = json!(100);
    cases.push(wanted);
    let mut wanted = table();
    wanted["daily_limit"] = json!(21);
    cases.push(wanted);
    for (index, wanted) in cases.into_iter().enumerate() {
        let (status, error) = setup
            .web(
                Method::PUT,
                &path,
                &setup.lehrer1,
                Some(json!({ "table": wanted })),
            )
            .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "case {index}");
        assert_eq!(error["code"], "invalid_request");
    }
    // A row is missing.
    let mut wanted = table();
    wanted.as_object_mut().unwrap().remove("daily");
    let (status, _) = setup
        .web(
            Method::PUT,
            &path,
            &setup.lehrer1,
            Some(json!({ "table": wanted })),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // Not a teacher of the group, and nobody at all.
    let (status, _) = setup.web(Method::GET, &path, &setup.lehrer2, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = setup
        .web(
            Method::PUT,
            &path,
            &setup.lehrer2,
            Some(json!({ "table": table() })),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = setup.call(Method::GET, &path, None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let (_, jobs) = setup.world(Method::GET, "/api/world/v1/jobs", None).await;
    assert_eq!(jobs["jobs"], json!([]));

    // A world that reports nonsense is not believed.
    let mut bad = table();
    bad["task"]["name"] = json!("steel");
    assert_eq!(setup.report("e2", bad).await, "invalid");
}
