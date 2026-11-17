//! Mails of the backend: what they say and how they leave.
//!
//! Sending by SMTP is not built yet. Until then every mail is written to
//! the terminal, which is also what the test environment wants.

use std::sync::{Arc, Mutex};

use anyhow::Result;

/// A mail, ready to send.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Mail {
    pub to: String,
    pub subject: String,
    pub body: String,
}

/// The way mails leave the backend.
#[derive(Debug, Clone)]
pub enum Mailer {
    /// Writes every mail to the terminal.
    Terminal,
    /// Keeps every mail, for the tests.
    Memory(Arc<Mutex<Vec<Mail>>>),
}

impl Mailer {
    /// Returns a mailer that keeps what it is given.
    pub fn memory() -> Self {
        Self::Memory(Arc::default())
    }

    pub async fn send(&self, mail: Mail) -> Result<()> {
        match self {
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

    /// Returns the mails a memory mailer has kept, oldest first.
    pub fn kept(&self) -> Vec<Mail> {
        match self {
            Self::Terminal => Vec::new(),
            Self::Memory(kept) => kept.lock().expect("the kept mails are broken").clone(),
        }
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
