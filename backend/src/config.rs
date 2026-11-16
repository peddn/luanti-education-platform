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

pub const DEFAULT_PUBLIC_URL: &str = "http://127.0.0.1:8080";
const DEFAULT_BIND: &str = "127.0.0.1:8080";
const DEFAULT_FRONTEND: &str = "frontend/dist";
const DEFAULT_DATABASE: &str = ".dev/backend/lep.sqlite";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub bind: SocketAddr,
    pub database: PathBuf,
    pub frontend: PathBuf,
    pub public_url: String,
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

        Ok(Self {
            bind,
            public_url,
            database: PathBuf::from(get(ENV_DATABASE, DEFAULT_DATABASE)),
            frontend: PathBuf::from(get(ENV_FRONTEND, DEFAULT_FRONTEND)),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
