//! Settings of the backend. They come from environment variables, so the
//! same program runs in the test environment and on a server.

use std::net::SocketAddr;
use std::path::PathBuf;

use anyhow::{bail, Context, Result};

/// Address the backend listens on.
pub const ENV_BIND: &str = "LEP_BIND";
/// Path of the SQLite database file.
pub const ENV_DATABASE: &str = "LEP_DATABASE";

/// Folder with the built frontend. It is served if it holds an
/// `index.html`.
pub const ENV_FRONTEND: &str = "LEP_FRONTEND";

/// Address of the web application as browsers reach it, for example
/// `https://lep.schule.example`. Links in mails start with it.
pub const ENV_PUBLIC_URL: &str = "LEP_PUBLIC_URL";

/// Name of the mail server. Without it mails are written to the
/// terminal instead of being sent.
pub const ENV_SMTP_HOST: &str = "LEP_SMTP_HOST";
/// Port of the mail server. The default follows from the security.
pub const ENV_SMTP_PORT: &str = "LEP_SMTP_PORT";
/// Name and password for the mail server, both or none.
pub const ENV_SMTP_USER: &str = "LEP_SMTP_USER";
pub const ENV_SMTP_PASSWORD: &str = "LEP_SMTP_PASSWORD";
/// How the connection to the mail server is protected: `starttls`
/// (default), `tls` or `none`.
pub const ENV_SMTP_SECURITY: &str = "LEP_SMTP_SECURITY";
/// Sender of the mails, for example `LEP <lep@schule.example>`.
pub const ENV_MAIL_FROM: &str = "LEP_MAIL_FROM";

pub const DEFAULT_PUBLIC_URL: &str = "http://127.0.0.1:8080";
const DEFAULT_BIND: &str = "127.0.0.1:8080";
const DEFAULT_FRONTEND: &str = "frontend/dist";
const DEFAULT_DATABASE: &str = ".dev/backend/lep.sqlite";

/// How the connection to the mail server is protected.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SmtpSecurity {
    /// Starts open and switches to TLS before anything is said. Usual on
    /// port 587.
    StartTls,
    /// TLS from the first byte. Usual on port 465.
    Tls,
    /// No protection. Only for a mail server on the same machine.
    None,
}

impl SmtpSecurity {
    fn default_port(self) -> u16 {
        match self {
            Self::StartTls => 587,
            Self::Tls => 465,
            Self::None => 25,
        }
    }
}

/// Settings for sending mail.
#[derive(Clone, PartialEq, Eq)]
pub struct Smtp {
    pub host: String,
    pub port: u16,
    pub security: SmtpSecurity,
    /// Name and password, if the mail server asks for them.
    pub login: Option<(String, String)>,
    pub from: String,
}

// Written by hand, so the password never ends up in a log.
impl std::fmt::Debug for Smtp {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Smtp")
            .field("host", &self.host)
            .field("port", &self.port)
            .field("security", &self.security)
            .field("user", &self.login.as_ref().map(|(user, _)| user))
            .field("from", &self.from)
            .finish()
    }
}

impl Smtp {
    /// Returns true if the mail server runs on this machine.
    fn is_local(&self) -> bool {
        matches!(self.host.as_str(), "localhost" | "127.0.0.1" | "::1")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub bind: SocketAddr,
    pub database: PathBuf,
    pub frontend: PathBuf,
    pub public_url: String,
    /// Settings for sending mail. Without them mails are written to the
    /// terminal.
    pub smtp: Option<Smtp>,
}

impl Config {
    /// Reads the settings from the environment of the process.
    pub fn from_env() -> Result<Self> {
        Self::from_lookup(|key| std::env::var(key).ok())
    }

    /// Reads the settings through `lookup`, which returns the value of a
    /// variable or `None`. Empty values count as not set.
    pub fn from_lookup(lookup: impl Fn(&str) -> Option<String>) -> Result<Self> {
        let get = |key: &str, default: &str| {
            lookup(key)
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| default.to_owned())
        };

        let bind = get(ENV_BIND, DEFAULT_BIND);
        let bind = bind
            .parse()
            .with_context(|| format!("{ENV_BIND} is not an address like 127.0.0.1:8080: {bind}"))?;

        let public_url = get(ENV_PUBLIC_URL, DEFAULT_PUBLIC_URL);
        let public_url = public_url.trim().trim_end_matches('/').to_owned();
        if !public_url.starts_with("http://") && !public_url.starts_with("https://") {
            bail!("{ENV_PUBLIC_URL} is not an address like https://lep.example: {public_url}");
        }

        let smtp = read_smtp(&lookup)?;

        Ok(Self {
            bind,
            public_url,
            smtp,
            database: PathBuf::from(get(ENV_DATABASE, DEFAULT_DATABASE)),
            frontend: PathBuf::from(get(ENV_FRONTEND, DEFAULT_FRONTEND)),
        })
    }
}

/// Reads the settings for sending mail. They have to fit together: a
/// backend that starts with half of them would fail later, at the first
/// mail, where nobody looks.
fn read_smtp(lookup: &impl Fn(&str) -> Option<String>) -> Result<Option<Smtp>> {
    let get = |key: &str| {
        lookup(key)
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty())
    };
    let Some(host) = get(ENV_SMTP_HOST) else {
        for key in [
            ENV_SMTP_PORT,
            ENV_SMTP_USER,
            ENV_SMTP_PASSWORD,
            ENV_SMTP_SECURITY,
            ENV_MAIL_FROM,
        ] {
            if get(key).is_some() {
                bail!("{key} is set, but {ENV_SMTP_HOST} is not: no mail would be sent");
            }
        }
        return Ok(None);
    };

    let security = match get(ENV_SMTP_SECURITY).as_deref() {
        None | Some("starttls") => SmtpSecurity::StartTls,
        Some("tls") => SmtpSecurity::Tls,
        Some("none") => SmtpSecurity::None,
        Some(other) => bail!("{ENV_SMTP_SECURITY} is not starttls, tls or none: {other}"),
    };
    let port = match get(ENV_SMTP_PORT) {
        Some(text) => text
            .parse()
            .ok()
            .filter(|port| *port != 0)
            .with_context(|| format!("{ENV_SMTP_PORT} is not a port like 587: {text}"))?,
        None => security.default_port(),
    };
    let login = match (get(ENV_SMTP_USER), get(ENV_SMTP_PASSWORD)) {
        (Some(user), Some(password)) => Some((user, password)),
        (None, None) => None,
        (Some(_), None) => bail!("{ENV_SMTP_USER} is set, but {ENV_SMTP_PASSWORD} is not"),
        (None, Some(_)) => bail!("{ENV_SMTP_PASSWORD} is set, but {ENV_SMTP_USER} is not"),
    };
    let from = get(ENV_MAIL_FROM).with_context(|| {
        format!("{ENV_SMTP_HOST} is set, but {ENV_MAIL_FROM} is not: mails need a sender")
    })?;

    let smtp = Smtp {
        host,
        port,
        security,
        login,
        from,
    };
    if smtp.security == SmtpSecurity::None && smtp.login.is_some() && !smtp.is_local() {
        bail!(
            "{ENV_SMTP_SECURITY} is none, but there is a password: it would cross the network in the clear"
        );
    }
    Ok(Some(smtp))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Reads the settings from pairs of variable and value.
    fn from_pairs(pairs: &[(&str, &str)]) -> Result<Config> {
        Config::from_lookup(|key| {
            pairs
                .iter()
                .find(|(name, _)| *name == key)
                .map(|(_, value)| (*value).to_owned())
        })
    }

    #[test]
    fn writes_mails_to_the_terminal_without_a_mail_server() {
        assert_eq!(from_pairs(&[]).unwrap().smtp, None);
    }

    #[test]
    fn reads_the_mail_server_with_defaults() {
        let config = from_pairs(&[
            (ENV_SMTP_HOST, " mail.schule.example "),
            (ENV_MAIL_FROM, "LEP <lep@schule.example>"),
        ])
        .unwrap();
        let smtp = config.smtp.unwrap();
        assert_eq!(smtp.host, "mail.schule.example");
        assert_eq!(smtp.port, 587);
        assert_eq!(smtp.security, SmtpSecurity::StartTls);
        assert_eq!(smtp.login, None);
        assert_eq!(smtp.from, "LEP <lep@schule.example>");
    }

    #[test]
    fn reads_every_setting_of_the_mail_server() {
        let config = from_pairs(&[
            (ENV_SMTP_HOST, "mail.schule.example"),
            (ENV_SMTP_SECURITY, "tls"),
            (ENV_SMTP_USER, "lep"),
            (ENV_SMTP_PASSWORD, "made-up"),
            (ENV_MAIL_FROM, "lep@schule.example"),
        ])
        .unwrap();
        let smtp = config.smtp.unwrap();
        assert_eq!(smtp.port, 465);
        assert_eq!(smtp.security, SmtpSecurity::Tls);
        assert_eq!(smtp.login, Some(("lep".to_owned(), "made-up".to_owned())));

        let other_port = from_pairs(&[
            (ENV_SMTP_HOST, "mail.schule.example"),
            (ENV_SMTP_PORT, "2525"),
            (ENV_MAIL_FROM, "lep@schule.example"),
        ])
        .unwrap();
        assert_eq!(other_port.smtp.unwrap().port, 2525);
    }

    #[test]
    fn the_password_stays_out_of_the_log() {
        let config = from_pairs(&[
            (ENV_SMTP_HOST, "mail.schule.example"),
            (ENV_SMTP_USER, "lep"),
            (ENV_SMTP_PASSWORD, "made-up-secret"),
            (ENV_MAIL_FROM, "lep@schule.example"),
        ])
        .unwrap();
        let shown = format!("{config:?}");
        assert!(shown.contains("mail.schule.example"));
        assert!(!shown.contains("made-up-secret"));
    }

    #[test]
    fn refuses_settings_for_mail_that_do_not_fit_together() {
        let host = (ENV_SMTP_HOST, "mail.schule.example");
        let from = (ENV_MAIL_FROM, "lep@schule.example");
        let cases: &[(&[(&str, &str)], &str)] = &[
            (&[from], ENV_SMTP_HOST),
            (&[(ENV_SMTP_PASSWORD, "made-up")], ENV_SMTP_HOST),
            (&[host], ENV_MAIL_FROM),
            (&[host, from, (ENV_SMTP_USER, "lep")], ENV_SMTP_PASSWORD),
            (&[host, from, (ENV_SMTP_PASSWORD, "made-up")], ENV_SMTP_USER),
            (&[host, from, (ENV_SMTP_PORT, "mail")], ENV_SMTP_PORT),
            (&[host, from, (ENV_SMTP_PORT, "0")], ENV_SMTP_PORT),
            (&[host, from, (ENV_SMTP_SECURITY, "ssl")], ENV_SMTP_SECURITY),
            (
                &[
                    host,
                    from,
                    (ENV_SMTP_SECURITY, "none"),
                    (ENV_SMTP_USER, "lep"),
                    (ENV_SMTP_PASSWORD, "made-up"),
                ],
                ENV_SMTP_SECURITY,
            ),
        ];
        for (pairs, named) in cases {
            let err = from_pairs(pairs).unwrap_err().to_string();
            assert!(err.contains(named), "{pairs:?}: {err}");
        }
    }

    #[test]
    fn allows_an_open_connection_to_a_mail_server_on_this_machine() {
        let config = from_pairs(&[
            (ENV_SMTP_HOST, "localhost"),
            (ENV_SMTP_SECURITY, "none"),
            (ENV_SMTP_USER, "lep"),
            (ENV_SMTP_PASSWORD, "made-up"),
            (ENV_MAIL_FROM, "lep@schule.example"),
        ])
        .unwrap();
        assert_eq!(config.smtp.unwrap().port, 25);
    }

    #[test]
    fn uses_defaults_without_variables() {
        let config = Config::from_lookup(|_| None).unwrap();
        assert_eq!(config.bind, "127.0.0.1:8080".parse().unwrap());
        assert_eq!(config.database, PathBuf::from(".dev/backend/lep.sqlite"));
        assert_eq!(config.frontend, PathBuf::from("frontend/dist"));
        assert_eq!(config.public_url, "http://127.0.0.1:8080");
    }

    #[test]
    fn reads_variables() {
        let config = Config::from_lookup(|key| match key {
            ENV_BIND => Some("0.0.0.0:9000".to_owned()),
            ENV_DATABASE => Some("/var/lib/lep/lep.sqlite".to_owned()),
            ENV_PUBLIC_URL => Some(" https://lep.example/ ".to_owned()),
            _ => None,
        })
        .unwrap();
        assert_eq!(config.bind, "0.0.0.0:9000".parse().unwrap());
        assert_eq!(config.database, PathBuf::from("/var/lib/lep/lep.sqlite"));
        assert_eq!(config.public_url, "https://lep.example");
    }

    #[test]
    fn treats_empty_values_as_not_set() {
        let config = Config::from_lookup(|_| Some("  ".to_owned())).unwrap();
        assert_eq!(config.bind, "127.0.0.1:8080".parse().unwrap());
    }

    #[test]
    fn rejects_a_public_address_without_scheme() {
        let result =
            Config::from_lookup(|key| (key == ENV_PUBLIC_URL).then(|| "lep.example".to_owned()));
        assert!(result.unwrap_err().to_string().contains(ENV_PUBLIC_URL));
    }

    #[test]
    fn rejects_an_address_that_is_none() {
        let result = Config::from_lookup(|key| (key == ENV_BIND).then(|| "nowhere".to_owned()));
        assert!(result.unwrap_err().to_string().contains(ENV_BIND));
    }
}
