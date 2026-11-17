//! Sending mail through a mail server. The mail server is a small one
//! that each test starts for itself on this machine; nothing leaves it.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use base64::Engine;
use lep_backend::config::{Smtp, SmtpSecurity};
use lep_backend::mail::{self, Mail, Mailer};
use mail_parser::MessageParser;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};

/// A mail as the mail server got it.
#[derive(Debug, Clone)]
struct Received {
    from: String,
    to: String,
    data: String,
}

/// How the mail server of a test behaves.
#[derive(Debug, Clone, Default)]
struct Behaviour {
    /// Name and password it asks for.
    login: Option<(String, String)>,
    /// Refuses every receiver.
    refuse_receiver: bool,
    /// Waits this long before it takes a mail.
    slow: Duration,
}

struct Server {
    port: u16,
    received: Arc<Mutex<Vec<Received>>>,
}

impl Server {
    async fn start(behaviour: Behaviour) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let received = Arc::new(Mutex::new(Vec::new()));
        let kept = received.clone();
        tokio::spawn(async move {
            while let Ok((stream, _)) = listener.accept().await {
                tokio::spawn(talk(stream, behaviour.clone(), kept.clone()));
            }
        });
        Self { port, received }
    }

    fn settings(&self, login: Option<(&str, &str)>) -> Smtp {
        Smtp {
            host: "127.0.0.1".to_owned(),
            port: self.port,
            security: SmtpSecurity::None,
            login: login.map(|(user, password)| (user.to_owned(), password.to_owned())),
            from: "LEP Schule <lep@schule.example>".to_owned(),
        }
    }

    fn received(&self) -> Vec<Received> {
        self.received.lock().unwrap().clone()
    }

    /// Waits until a mail has arrived, for mails sent in the background.
    async fn wait_for_mail(&self) -> Received {
        for _ in 0..100 {
            if let Some(mail) = self.received().pop() {
                return mail;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        panic!("no mail arrived");
    }
}

/// Speaks as much SMTP as the backend needs.
async fn talk(stream: TcpStream, behaviour: Behaviour, kept: Arc<Mutex<Vec<Received>>>) {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    let mut logged_in = behaviour.login.is_none();
    let (mut from, mut to) = (String::new(), String::new());
    let _ = write.write_all(b"220 test server\r\n").await;

    while let Ok(Some(line)) = lines.next_line().await {
        let upper = line.to_ascii_uppercase();
        let answer: String = if upper.starts_with("EHLO") {
            "250-test server\r\n250-8BITMIME\r\n250 AUTH PLAIN\r\n".to_owned()
        } else if upper.starts_with("AUTH PLAIN") {
            let (user, password) = behaviour.login.clone().unwrap_or_default();
            let expected =
                base64::engine::general_purpose::STANDARD.encode(format!("\0{user}\0{password}"));
            logged_in = line.ends_with(&expected);
            if logged_in {
                "235 2.7.0 welcome\r\n".to_owned()
            } else {
                "535 5.7.8 wrong name or password\r\n".to_owned()
            }
        } else if upper.starts_with("MAIL FROM:") {
            if logged_in {
                from = line[10..]
                    .split_whitespace()
                    .next()
                    .unwrap_or("")
                    .to_owned();
                "250 ok\r\n".to_owned()
            } else {
                "530 5.7.0 log in first\r\n".to_owned()
            }
        } else if upper.starts_with("RCPT TO:") {
            if behaviour.refuse_receiver {
                format!("550 5.1.1 {}: no such mailbox\r\n", &line[8..])
            } else {
                to = line[8..].to_owned();
                "250 ok\r\n".to_owned()
            }
        } else if upper == "DATA" {
            let _ = write.write_all(b"354 go on\r\n").await;
            let mut data = String::new();
            while let Ok(Some(line)) = lines.next_line().await {
                if line == "." {
                    break;
                }
                data.push_str(line.strip_prefix('.').unwrap_or(&line));
                data.push_str("\r\n");
            }
            tokio::time::sleep(behaviour.slow).await;
            kept.lock().unwrap().push(Received {
                from: from.clone(),
                to: to.clone(),
                data,
            });
            "250 taken\r\n".to_owned()
        } else if upper == "QUIT" {
            let _ = write.write_all(b"221 bye\r\n").await;
            return;
        } else {
            // NOOP, RSET and whatever else is polite.
            "250 ok\r\n".to_owned()
        };
        if write.write_all(answer.as_bytes()).await.is_err() {
            return;
        }
    }
}

fn letter() -> Mail {
    Mail {
        to: "anna@schule.example".to_owned(),
        subject: "Bestätigung für Frau Müller".to_owned(),
        body: "Grüße aus der Schule.\nÄ Ö Ü ß, und eine lange Zeile mit einem Link: \
               https://lep.schule.example/login?token=lepl_0123456789abcdef0123456789abcdef0123456789abcdef"
            .to_owned(),
    }
}

#[tokio::test]
async fn a_mail_arrives_as_it_was_written() {
    let server = Server::start(Behaviour::default()).await;
    let mailer = Mailer::smtp(&server.settings(None)).unwrap();
    mailer.check().await.unwrap();
    mailer.send(letter()).await.unwrap();

    let received = server.received();
    assert_eq!(received.len(), 1);
    assert_eq!(received[0].from, "<lep@schule.example>");
    assert_eq!(received[0].to, "<anna@schule.example>");

    // What a mail program makes of it: umlauts and the link survive.
    let message = MessageParser::default().parse(&received[0].data).unwrap();
    assert_eq!(message.subject(), Some("Bestätigung für Frau Müller"));
    assert_eq!(
        message.from().unwrap().first().unwrap().name(),
        Some("LEP Schule")
    );
    assert_eq!(
        message.to().unwrap().first().unwrap().address(),
        Some("anna@schule.example")
    );
    let body = message.body_text(0).unwrap();
    assert_eq!(body.trim_end().replace("\r\n", "\n"), letter().body);
    assert!(received[0]
        .data
        .to_lowercase()
        .contains("content-type: text/plain; charset=utf-8"));
    assert!(message.date().is_some());
    assert!(message.message_id().is_some());
}

#[tokio::test]
async fn the_real_mails_carry_their_links() {
    let server = Server::start(Behaviour::default()).await;
    let mailer = Mailer::smtp(&server.settings(None)).unwrap();
    let mail = mail::login(
        "https://lep.schule.example",
        "anna@schule.example",
        "lehrer1",
        "lepl_abc",
        15,
    );
    mailer.send(mail).await.unwrap();
    mailer
        .send(mail::test("anna@schule.example"))
        .await
        .unwrap();

    let received = server.received();
    let parser = MessageParser::default();
    let login = parser.parse(&received[0].data).unwrap();
    let body = login.body_text(0).unwrap();
    assert_eq!(
        body.matches("https://lep.schule.example/login?token=lepl_abc")
            .count(),
        2
    );
    assert!(body.contains("Der Link gilt 15 Minuten"));
    let test = parser.parse(&received[1].data).unwrap();
    assert!(test.body_text(0).unwrap().contains("ä ö ü ß"));
}

#[tokio::test]
async fn the_mail_server_can_ask_for_a_login() {
    let behaviour = Behaviour {
        login: Some(("lep".to_owned(), "made-up".to_owned())),
        ..Behaviour::default()
    };
    let server = Server::start(behaviour).await;

    let right = Mailer::smtp(&server.settings(Some(("lep", "made-up")))).unwrap();
    right.check().await.unwrap();
    right.send(letter()).await.unwrap();
    assert_eq!(server.received().len(), 1);

    let wrong = Mailer::smtp(&server.settings(Some(("lep", "guessed")))).unwrap();
    assert!(wrong.check().await.is_err());
    assert!(wrong.send(letter()).await.is_err());
    let none = Mailer::smtp(&server.settings(None)).unwrap();
    assert!(none.send(letter()).await.is_err());
    assert_eq!(server.received().len(), 1);
}

#[tokio::test]
async fn a_refused_mail_is_an_error() {
    let behaviour = Behaviour {
        refuse_receiver: true,
        ..Behaviour::default()
    };
    let server = Server::start(behaviour).await;
    let mailer = Mailer::smtp(&server.settings(None)).unwrap();
    let err = format!("{:#}", mailer.send(letter()).await.unwrap_err());
    assert!(err.contains("did not take the mail"), "{err}");
    assert!(server.received().is_empty());

    // In the background a failure is written to the log and nothing else
    // happens.
    mailer.send_later(letter(), "lehrer1").await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(server.received().is_empty());
}

#[tokio::test]
async fn a_mail_server_that_is_not_there_is_an_error() {
    // A port nobody listens on: bind one and let it go again.
    let port = TcpListener::bind("127.0.0.1:0")
        .await
        .unwrap()
        .local_addr()
        .unwrap()
        .port();
    let settings = Smtp {
        host: "127.0.0.1".to_owned(),
        port,
        security: SmtpSecurity::None,
        login: None,
        from: "lep@schule.example".to_owned(),
    };
    let mailer = Mailer::smtp(&settings).unwrap();
    assert!(mailer.check().await.is_err());
    assert!(mailer.send(letter()).await.is_err());
}

#[tokio::test]
async fn an_address_that_is_none_is_an_error_before_anything_is_sent() {
    let server = Server::start(Behaviour::default()).await;
    let mailer = Mailer::smtp(&server.settings(None)).unwrap();
    let mut mail = letter();
    mail.to = "not an address".to_owned();
    assert!(mailer.send(mail).await.is_err());
    assert!(server.received().is_empty());
}

#[tokio::test]
async fn nobody_waits_for_the_mail_server() {
    use axum::body::Body;
    use axum::http::{header, Request, StatusCode};
    use lep_backend::app::{self, AppState};
    use lep_backend::{db, teachers, worlds};
    use lep_protocol::world::{WebAccessAction, WebAccessRequest};
    use tower::ServiceExt;

    let slow = Duration::from_millis(600);
    let server = Server::start(Behaviour {
        slow,
        ..Behaviour::default()
    })
    .await;

    // A teacher with a confirmed address.
    let pool = db::open_in_memory().await.unwrap();
    let (world, _) = worlds::add(&pool, "7b").await.unwrap();
    teachers::set_holders(&pool, &world.id, &["lehrer1".to_owned()])
        .await
        .unwrap();
    let set = WebAccessRequest {
        account: "lehrer1".to_owned(),
        action: WebAccessAction::Set,
        email: Some("anna@schule.example".to_owned()),
    };
    let Some(teachers::Change::Mail { token, .. }) =
        teachers::request(&pool, &set, 0).await.unwrap()
    else {
        panic!("expected a mail");
    };
    teachers::confirm(&pool, &token, 1).await.unwrap().unwrap();

    let mailer = Mailer::smtp(&server.settings(None)).unwrap();
    let state = AppState::with(pool, mailer, "https://lep.schule.example");
    let ask = |email: &'static str| {
        let request = Request::post("/api/web/v1/login/link")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(format!("{{\"email\":\"{email}\"}}")))
            .unwrap();
        app::router(state.clone()).oneshot(request)
    };

    // Known or not: the answer is there long before the mail server is
    // done.
    for email in ["anna@schule.example", "fremd@schule.example"] {
        let started = Instant::now();
        let response = ask(email).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert!(
            started.elapsed() < slow / 2,
            "{email} took {:?}",
            started.elapsed()
        );
    }

    let mail = server.wait_for_mail().await;
    assert_eq!(mail.to, "<anna@schule.example>");
    let message = MessageParser::default().parse(&mail.data).unwrap();
    assert!(message
        .body_text(0)
        .unwrap()
        .contains("https://lep.schule.example/login?token=lepl_"));
    assert_eq!(server.received().len(), 1);
}
