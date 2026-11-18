//! Mails of the backend: what they say and how they leave.
//!
//! With a mail server in the settings they are sent by SMTP. Without one
//! every mail is written to the terminal, which is what the test
//! environment wants.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Context, Result};
use lettre::message::header::ContentType;
use lettre::message::Mailbox;
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor};

use crate::config::{Smtp, SmtpSecurity};

/// Longest time a step of the talk with the mail server may take.
const SMTP_TIMEOUT: Duration = Duration::from_secs(20);

/// A mail, ready to send.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Mail {
    pub to: String,
    pub subject: String,
    pub body: String,
}

/// A connection to a mail server and the sender of the mails.
pub struct SmtpSender {
    transport: AsyncSmtpTransport<Tokio1Executor>,
    from: Mailbox,
}

// Written by hand: the transport holds the password.
impl std::fmt::Debug for SmtpSender {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SmtpSender")
            .field("from", &self.from.to_string())
            .finish_non_exhaustive()
    }
}

/// The way mails leave the backend.
#[derive(Debug, Clone)]
pub enum Mailer {
    /// Writes every mail to the terminal.
    Terminal,
    /// Keeps every mail, for the tests.
    Memory(Arc<Mutex<Vec<Mail>>>),
    /// Sends every mail through a mail server.
    Smtp(Arc<SmtpSender>),
}

impl Mailer {
    /// Returns a mailer that keeps what it is given.
    pub fn memory() -> Self {
        Self::Memory(Arc::default())
    }

    /// Returns the mailer the settings ask for: through the mail server,
    /// or to the terminal without one.
    pub fn from_settings(smtp: Option<&Smtp>) -> Result<Self> {
        smtp.map_or(Ok(Self::Terminal), Self::smtp)
    }

    /// Returns a mailer that sends through a mail server. Nothing is
    /// connected yet; that happens with the first mail.
    pub fn smtp(settings: &Smtp) -> Result<Self> {
        let from: Mailbox = settings.from.parse().with_context(|| {
            format!(
                "{} is not a sender like LEP <lep@schule.example>: {}",
                crate::config::ENV_MAIL_FROM,
                settings.from
            )
        })?;
        let host = settings.host.as_str();
        let mut builder = match settings.security {
            SmtpSecurity::StartTls => AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(host),
            SmtpSecurity::Tls => AsyncSmtpTransport::<Tokio1Executor>::relay(host),
            SmtpSecurity::None => Ok(AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(
                host,
            )),
        }
        .with_context(|| format!("cannot prepare the connection to the mail server {host}"))?
        .port(settings.port)
        .timeout(Some(SMTP_TIMEOUT));
        if let Some((user, password)) = &settings.login {
            builder = builder.credentials(Credentials::new(user.clone(), password.clone()));
        }
        Ok(Self::Smtp(Arc::new(SmtpSender {
            transport: builder.build(),
            from,
        })))
    }

    /// Returns true if mails really leave, through a mail server.
    pub fn is_smtp(&self) -> bool {
        matches!(self, Self::Smtp(_))
    }

    /// Checks that the mail server answers and accepts the login.
    /// Without a mail server there is nothing to check.
    pub async fn check(&self) -> Result<()> {
        if let Self::Smtp(sender) = self {
            let alive = sender
                .transport
                .test_connection()
                .await
                .context("the mail server does not accept the connection")?;
            anyhow::ensure!(alive, "the mail server does not answer as a mail server");
        }
        Ok(())
    }

    /// Sends a mail and waits until the mail server has taken it.
    pub async fn send(&self, mail: Mail) -> Result<()> {
        match self {
            Self::Smtp(sender) => {
                let to: Mailbox = mail
                    .to
                    .parse()
                    .context("the address of the receiver cannot be used")?;
                let message = Message::builder()
                    .from(sender.from.clone())
                    .to(to)
                    .subject(mail.subject)
                    // An id of its own: spam filters distrust mails
                    // without one.
                    .message_id(None)
                    .header(ContentType::TEXT_PLAIN)
                    .body(mail.body)
                    .context("cannot build the mail")?;
                sender
                    .transport
                    .send(message)
                    .await
                    .context("the mail server did not take the mail")?;
            }
            Self::Terminal => {
                println!(
                    "\n----- mail (not sent, mail is not set up) -----\nTo: {}\nSubject: {}\n\n{}\n-----------------------------------------------\n",
                    mail.to, mail.subject, mail.body
                );
            }
            Self::Memory(kept) => kept.lock().expect("the kept mails are broken").push(mail),
        }
        Ok(())
    }

    /// Sends a mail without making the caller wait for the mail server.
    /// Whoever asked for the mail gets the same answer at the same speed,
    /// whether or not a mail goes out. A failure is written to the log
    /// with the account, without the address.
    pub async fn send_later(&self, mail: Mail, account: &str) {
        let to = mail.to.clone();
        let account = account.to_owned();
        let mailer = self.clone();
        let work = async move {
            if let Err(err) = mailer.send(mail).await {
                let reason = hide_address(&format!("{err:#}"), &to);
                tracing::error!(%account, "cannot send a mail: {reason}");
            }
        };
        if self.is_smtp() {
            tokio::spawn(work);
        } else {
            // Terminal and tests: at once, so the mail is there when the
            // answer is.
            work.await;
        }
    }

    /// Returns the mails a memory mailer has kept, oldest first.
    pub fn kept(&self) -> Vec<Mail> {
        match self {
            Self::Memory(kept) => kept.lock().expect("the kept mails are broken").clone(),
            Self::Terminal | Self::Smtp(_) => Vec::new(),
        }
    }
}

/// Removes an address from a text for the log. Mail servers like to
/// repeat the receiver in their answers.
fn hide_address(text: &str, address: &str) -> String {
    if address.is_empty() {
        return text.to_owned();
    }
    text.replace(address, "(address)")
}

/// Builds the mail of the command that tries out the mail server.
pub fn test(to: &str) -> Mail {
    Mail {
        to: to.to_owned(),
        subject: "Luanti Education Platform: Probemail / Test mail".to_owned(),
        body: "Diese Mail zeigt, dass der Mailversand der Luanti Education Platform \
               eingerichtet ist. Umlaute kommen an: ä ö ü ß.\n\
               \n\
               ----\n\
               \n\
               This mail shows that the Luanti Education Platform can send mail."
            .to_owned(),
    }
}

/// Returns the address of the page that confirms an address.
pub fn confirmation_link(public_url: &str, token: &str) -> String {
    format!("{}/confirm?token={token}", public_url.trim_end_matches('/'))
}

/// Returns the address of the page that logs in.
pub fn login_link(public_url: &str, token: &str) -> String {
    format!("{}/login?token={token}", public_url.trim_end_matches('/'))
}

/// Builds the mail with the link that logs a teacher in, in German and
/// English.
pub fn login(public_url: &str, to: &str, account: &str, token: &str, minutes: i64) -> Mail {
    let link = login_link(public_url, token);
    let body = format!(
        "Hallo {account},\n\
         \n\
         mit diesem Link meldest du dich bei der Luanti Education Platform an:\n\
         \n\
         {link}\n\
         \n\
         Der Link gilt {minutes} Minuten und nur einmal. Hast du ihn nicht \
         angefordert, dann ignoriere diese Mail. Ohne den Link kommt niemand hinein.\n\
         \n\
         ----\n\
         \n\
         Hello {account},\n\
         \n\
         this link logs you in to the Luanti Education Platform:\n\
         \n\
         {link}\n\
         \n\
         The link works for {minutes} minutes and only once. If you did not ask \
         for it, ignore this mail. Nobody gets in without the link."
    );
    Mail {
        to: to.to_owned(),
        subject: "Luanti Education Platform: Anmelden / Log in".to_owned(),
        body,
    }
}

/// Builds the mail that tells a teacher of a group about a new display
/// name, in German and English. Nobody approves names, so the teachers
/// hear of each one. The mail goes to an address the teacher confirmed.
pub fn display_name(
    public_url: &str,
    to: &str,
    teacher: &str,
    group: &str,
    group_id: &str,
    account: &str,
    name: &str,
) -> Mail {
    let link = format!(
        "{}/groups/{group_id}/students",
        public_url.trim_end_matches('/')
    );
    let body = format!(
        "Hallo {teacher},\n\
         \n\
         in der Gruppe {group} hat sich ein Konto einen neuen Wunschnamen gegeben:\n\
         \n\
         Konto: {account}\n\
         Wunschname: {name}\n\
         \n\
         Niemand hat den Namen vorab geprüft. Passt er nicht, kannst du ihn hier \
         entfernen und dem Konto das Wählen sperren:\n\
         \n\
         {link}\n\
         \n\
         ----\n\
         \n\
         Hello {teacher},\n\
         \n\
         an account of the group {group} has chosen a new display name:\n\
         \n\
         Account: {account}\n\
         Display name: {name}\n\
         \n\
         Nobody checked the name beforehand. If it does not fit, you can take it \
         away and lock choosing a name for the account here:\n\
         \n\
         {link}"
    );
    Mail {
        to: to.to_owned(),
        subject: format!(
            "Luanti Education Platform: Neuer Wunschname in {group} / New display name"
        ),
        body,
    }
}

/// Builds the mail that asks a teacher to confirm their address. The
/// backend does not know the language of the teacher, so the mail speaks
/// German and English.
pub fn confirmation(public_url: &str, to: &str, account: &str, token: &str, minutes: i64) -> Mail {
    let link = confirmation_link(public_url, token);
    let body = format!(
        "Hallo {account},\n\
         \n\
         du hast am Lehrerpult diese E-Mail-Adresse für deinen Web-Zugang zur \
         Luanti Education Platform eingetragen. Bitte bestätige sie über diesen Link:\n\
         \n\
         {link}\n\
         \n\
         Der Link gilt {minutes} Minuten und nur einmal. Warst du das nicht, \
         dann ignoriere diese Mail. Ohne Bestätigung geschieht nichts.\n\
         \n\
         ----\n\
         \n\
         Hello {account},\n\
         \n\
         you entered this e-mail address at the teacher's desk for your web access \
         to the Luanti Education Platform. Please confirm it with this link:\n\
         \n\
         {link}\n\
         \n\
         The link works for {minutes} minutes and only once. If this was not you, \
         ignore this mail. Nothing happens without the confirmation."
    );
    Mail {
        to: to.to_owned(),
        subject:
            "Luanti Education Platform: E-Mail-Adresse bestätigen / Confirm your e-mail address"
                .to_owned(),
        body,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_link_needs_no_slash_at_the_end_of_the_address() {
        assert_eq!(
            confirmation_link("https://lep.example/", "abc"),
            "https://lep.example/confirm?token=abc"
        );
        assert_eq!(
            confirmation_link("http://127.0.0.1:8080", "abc"),
            "http://127.0.0.1:8080/confirm?token=abc"
        );
    }

    #[test]
    fn the_mail_speaks_both_languages_and_carries_the_link() {
        let mail = confirmation(
            "https://lep.example",
            "t@schule.example",
            "lehrer1",
            "tok",
            15,
        );
        assert_eq!(mail.to, "t@schule.example");
        assert!(mail.body.contains("Hallo lehrer1"));
        assert!(mail.body.contains("Hello lehrer1"));
        assert_eq!(
            mail.body
                .matches("https://lep.example/confirm?token=tok")
                .count(),
            2
        );
        assert!(mail.body.contains("15 Minuten"));
        assert!(mail.body.contains("15 minutes"));
    }

    #[test]
    fn the_login_mail_speaks_both_languages_and_carries_the_link() {
        let mail = login(
            "https://lep.example/",
            "t@schule.example",
            "lehrer1",
            "tok",
            15,
        );
        assert_eq!(mail.to, "t@schule.example");
        assert!(mail.body.contains("Hallo lehrer1"));
        assert!(mail.body.contains("Hello lehrer1"));
        assert_eq!(
            mail.body
                .matches("https://lep.example/login?token=tok")
                .count(),
            2
        );
    }

    #[test]
    fn hides_the_address_in_what_a_mail_server_says() {
        assert_eq!(
            hide_address(
                "550 5.1.1 <anna@schule.example>: unknown",
                "anna@schule.example"
            ),
            "550 5.1.1 <(address)>: unknown"
        );
        assert_eq!(hide_address("timed out", ""), "timed out");
    }

    // The connection pool of the mailer needs the runtime.
    #[tokio::test]
    async fn refuses_a_sender_that_is_none() {
        let settings = |from: &str| Smtp {
            host: "mail.schule.example".to_owned(),
            port: 587,
            security: SmtpSecurity::StartTls,
            login: Some(("lep".to_owned(), "made-up-secret".to_owned())),
            from: from.to_owned(),
        };
        let err = Mailer::smtp(&settings("not a sender"))
            .unwrap_err()
            .to_string();
        assert!(err.contains("LEP_MAIL_FROM"), "{err}");

        let mailer = Mailer::smtp(&settings("LEP <lep@schule.example>")).unwrap();
        assert!(mailer.is_smtp());
        // The password is not part of what a log would show.
        assert!(!format!("{mailer:?}").contains("made-up-secret"));
        assert!(!Mailer::from_settings(None).unwrap().is_smtp());
    }

    #[tokio::test]
    async fn a_memory_mailer_keeps_its_mails() {
        let mailer = Mailer::memory();
        let mail = confirmation(
            "https://lep.example",
            "t@schule.example",
            "lehrer1",
            "tok",
            15,
        );
        mailer.send(mail.clone()).await.unwrap();
        assert_eq!(mailer.kept(), vec![mail]);
        assert!(Mailer::Terminal.kept().is_empty());
    }
}
