//! Types of the interface between the LEP backend, the worlds and the web
//! frontend.
//!
//! Every message that crosses a process boundary is defined here, once.
//! The backend builds its OpenAPI description from these types, and the
//! types of the frontend and the checks of the Lua mods are generated from
//! that description.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// Whether the backend can do its work.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum HealthStatus {
    /// Everything the backend needs is available.
    Ok,
    /// The backend answers, but something it needs does not.
    Degraded,
}

/// Answer of the health check.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct Health {
    pub status: HealthStatus,
    /// Version of the backend, as in its package.
    pub version: String,
    /// True if the database answers.
    pub database: bool,
}

impl Health {
    /// Builds the answer from the one thing that can be missing so far.
    pub fn new(version: impl Into<String>, database: bool) -> Self {
        Self {
            status: if database {
                HealthStatus::Ok
            } else {
                HealthStatus::Degraded
            },
            version: version.into(),
            database,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn health_is_ok_with_a_database() {
        let health = Health::new("1.2.3", true);
        assert_eq!(health.status, HealthStatus::Ok);
        assert_eq!(health.version, "1.2.3");
    }

    #[test]
    fn health_is_degraded_without_a_database() {
        assert_eq!(Health::new("1.2.3", false).status, HealthStatus::Degraded);
    }
}
