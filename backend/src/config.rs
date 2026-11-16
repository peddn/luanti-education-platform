//! Settings of the backend. They come from environment variables, so the
//! same program runs in the test environment and on a server.

use std::net::SocketAddr;
use std::path::PathBuf;

use anyhow::{Context, Result};

/// Address the backend listens on.
pub const ENV_BIND: &str = "LEP_BIND";
/// Path of the SQLite database file.
pub const ENV_DATABASE: &str = "LEP_DATABASE";

const DEFAULT_BIND: &str = "127.0.0.1:8080";
const DEFAULT_DATABASE: &str = ".dev/backend/lep.sqlite";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub bind: SocketAddr,
    pub database: PathBuf,
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

        Ok(Self {
            bind,
            database: PathBuf::from(get(ENV_DATABASE, DEFAULT_DATABASE)),
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
    }

    #[test]
    fn reads_variables() {
        let config = Config::from_lookup(|key| match key {
            ENV_BIND => Some("0.0.0.0:9000".to_owned()),
            ENV_DATABASE => Some("/var/lib/lep/lep.sqlite".to_owned()),
            _ => None,
        })
        .unwrap();
        assert_eq!(config.bind, "0.0.0.0:9000".parse().unwrap());
        assert_eq!(config.database, PathBuf::from("/var/lib/lep/lep.sqlite"));
    }

    #[test]
    fn treats_empty_values_as_not_set() {
        let config = Config::from_lookup(|_| Some("  ".to_owned())).unwrap();
        assert_eq!(config.bind, "127.0.0.1:8080".parse().unwrap());
    }

    #[test]
    fn rejects_an_address_that_is_none() {
        let result = Config::from_lookup(|key| (key == ENV_BIND).then(|| "nowhere".to_owned()));
        assert!(result.unwrap_err().to_string().contains(ENV_BIND));
    }
}
