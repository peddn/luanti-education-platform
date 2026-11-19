//! The protocols of a world in the interface for the browser: reading,
//! filtering, the rights and the export. Called without a network.

use std::time::Duration;

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
    fn protocol(&self, group: &str, name: &str) -> String {
        format!("/api/web/v1/groups/{group}/protocols/{name}")
    }

    /// Writes entries into protocols as the world of the first group.
    async fn write(&self, entries: &[(&str, i64, &str, Value)]) {
        let events: Vec<Value> = entries
            .iter()
            .enumerate()
            .map(|(index, (protocol, time, account, fields))| {
                json!({ "id": format!("e{index}-{time}"), "kind": "protocol", "time": time,
                    "payload": { "protocol": protocol, "account": account, "fields": fields } })
            })
            .collect();
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

    /// Fetches a file as a teacher: status, headers and the text.
    async fn download(&self, path: &str, session: &str) -> (StatusCode, HeaderMap, String) {
        let request = Request::builder()
            .uri(path)
            .header(header::COOKIE, format!("lep_session={session}"))
            .body(Body::empty())
            .unwrap();
        let response = app::router(self.state.clone())
            .oneshot(request)
            .await
            .unwrap();
        let status = response.status();
        let headers = response.headers().clone();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        (status, headers, String::from_utf8(bytes.to_vec()).unwrap())
    }
}

fn texts(page: &Value) -> Vec<&str> {
    page["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["fields"]["text"].as_str().unwrap())
        .collect()
}

#[tokio::test]
async fn a_teacher_reads_and_narrows_down_the_protocols_of_the_group() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    setup
        .write(&[
            ("chat", 1700000000, "klugeEule", json!({ "kind": "chat", "text": "hallo" })),
            ("chat", 1700000100, "frohesReh", json!({ "kind": "chat", "text": "selber hallo" })),
            ("chat", 1700000200, "klugeEule", json!({ "kind": "action", "text": "winkt" })),
            ("rewards", 1700000300, "klugeEule", json!({ "size": "small", "reason": "task",
                "module": "lep_math:math", "level": "1", "task": "add", "items": "default:apple 1" })),
        ])
        .await;
    let chat = setup.protocol(&setup.first, "chat");

    let (status, page) = setup.web(Method::GET, &chat, &teacher, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(page["columns"], json!(["kind", "recipient", "text"]));
    assert_eq!(texts(&page), ["winkt", "selber hallo", "hallo"]);
    assert_eq!(page["more"], false);
    assert_eq!(page["entries"][0]["account"], "klugeEule");
    assert_eq!(page["entries"][0]["time"], 1700000200);

    let (_, page) = setup
        .web(
            Method::GET,
            &format!("{chat}?account=klugeEule"),
            &teacher,
            None,
        )
        .await;
    assert_eq!(texts(&page), ["winkt", "hallo"]);
    let (_, page) = setup
        .web(
            Method::GET,
            &format!("{chat}?since=1700000100&account="),
            &teacher,
            None,
        )
        .await;
    assert_eq!(texts(&page), ["winkt", "selber hallo"]);
    // The next page, and what arrived since.
    let oldest_shown = page["entries"][1]["id"].as_i64().unwrap();
    let (_, older) = setup
        .web(
            Method::GET,
            &format!("{chat}?before={oldest_shown}"),
            &teacher,
            None,
        )
        .await;
    assert_eq!(texts(&older), ["hallo"]);
    let (_, newer) = setup
        .web(
            Method::GET,
            &format!("{chat}?after={oldest_shown}"),
            &teacher,
            None,
        )
        .await;
    assert_eq!(texts(&newer), ["winkt"]);

    let (_, rewards) = setup
        .web(
            Method::GET,
            &setup.protocol(&setup.first, "rewards"),
            &teacher,
            None,
        )
        .await;
    assert_eq!(rewards["entries"][0]["fields"]["items"], "default:apple 1");
    assert_eq!(rewards["columns"][0], "size");

    let (status, json) = setup
        .web(
            Method::GET,
            &format!("{chat}?since=gestern"),
            &teacher,
            None,
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{json}");
}

#[tokio::test]
async fn the_protocol_of_the_desk_is_for_the_administration_only() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let stranger = log_in(&setup.state.db, "lehrer2").await;
    let administration = log_in(&setup.state.db, "leitung").await;
    setup
        .write(&[(
            "desk",
            1700000000,
            "lehrer1",
            json!({ "action": "mute", "targets": "klugeEule" }),
        )])
        .await;
    let desk = setup.protocol(&setup.first, "desk");
    let chat = setup.protocol(&setup.first, "chat");

    for path in [desk.clone(), format!("{desk}/export")] {
        let (status, json) = setup.web(Method::GET, &path, &teacher, None).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{path}");
        assert_eq!(json["code"], "forbidden");
    }
    let (status, page) = setup.web(Method::GET, &desk, &administration, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(page["entries"][0]["fields"]["action"], "mute");
    let (status, _, file) = setup
        .download(&format!("{desk}/export"), &administration)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert!(file.contains("lehrer1;;mute;klugeEule"));

    // Who does not teach the group reads none of its protocols.
    for path in [chat.clone(), format!("{chat}/export"), desk.clone()] {
        let (status, json) = setup.web(Method::GET, &path, &stranger, None).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{path}");
        assert_eq!(json["code"], "not_found");
        let (status, _, _) = setup.call(Method::GET, &path, None, None).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{path}");
    }
    for name in ["passwords", "CHAT", "chat%2F..%2Fdesk"] {
        let path = setup.protocol(&setup.first, name);
        let (status, _) = setup.web(Method::GET, &path, &administration, None).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{name}");
    }
    // The other group has its own protocols.
    let (_, page) = setup
        .web(
            Method::GET,
            &setup.protocol(&setup.second, "desk"),
            &administration,
            None,
        )
        .await;
    assert_eq!(page["entries"], json!([]));
}

#[tokio::test]
async fn the_export_is_a_file_with_the_filtered_entries() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    setup
        .write(&[
            (
                "chat",
                1700000000,
                "klugeEule",
                json!({ "kind": "chat", "text": "hallo; du" }),
            ),
            (
                "chat",
                1700000060,
                "frohesReh",
                json!({ "kind": "chat", "text": "=1+1" }),
            ),
        ])
        .await;
    let export = format!("{}/export", setup.protocol(&setup.first, "chat"));

    let (status, headers, file) = setup.download(&export, &teacher).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers[header::CONTENT_TYPE], "text/csv; charset=utf-8");
    assert_eq!(
        headers[header::CONTENT_DISPOSITION],
        "attachment; filename=\"protokoll-chat-7b.csv\""
    );
    assert_eq!(headers[header::CACHE_CONTROL], "no-store");
    assert_eq!(
        file,
        "\u{feff}time_utc;account;display_name;kind;recipient;text\r\n\
         2023-11-14 22:13:20;klugeEule;;chat;;\"hallo; du\"\r\n\
         2023-11-14 22:14:20;frohesReh;;chat;;'=1+1\r\n"
    );
    let (_, _, file) = setup
        .download(
            &format!("{export}?account=frohesReh&since=1700000000"),
            &teacher,
        )
        .await;
    assert_eq!(file.lines().count(), 2);
    assert!(file.contains("frohesReh"));
}

#[tokio::test]
async fn an_open_page_hears_of_new_entries() {
    let setup = Setup::new().await;
    let teacher = log_in(&setup.state.db, "lehrer1").await;
    let request = Request::builder()
        .uri(format!("/api/web/v1/groups/{}/changes", setup.first))
        .header(header::COOKIE, format!("lep_session={teacher}"))
        .body(Body::empty())
        .unwrap();
    let mut stream = app::router(setup.state.clone())
        .oneshot(request)
        .await
        .unwrap()
        .into_body();
    setup
        .write(&[(
            "chat",
            1700000000,
            "klugeEule",
            json!({ "kind": "chat", "text": "hallo" }),
        )])
        .await;
    let frame = tokio::time::timeout(Duration::from_secs(2), stream.frame())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(
        frame.into_data().unwrap(),
        "event: change\ndata: protocols\n\n"
    );
}
