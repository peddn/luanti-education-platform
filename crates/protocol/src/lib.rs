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

/// Interface for the worlds: what a Luanti world and the backend say to
/// each other. The world always calls, the backend only answers.
pub mod world {
    use serde::{Deserialize, Serialize};
    use serde_json::Value;
    use utoipa::ToSchema;

    /// Most events a world sends in one request.
    pub const MAX_BATCH: usize = 100;
    /// Longest time in seconds a request for jobs stays open.
    pub const MAX_WAIT_SECONDS: u64 = 25;

    /// Kind of the event a world sends when it has started.
    pub const EVENT_WORLD_STARTED: &str = "world_started";
    /// Kind of the job that only checks the way to the world and back.
    pub const JOB_PING: &str = "ping";

    /// One thing that happened in a world.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
    pub struct Event {
        /// Unique id, made up by the world. The backend uses it to notice
        /// an event it has seen before.
        pub id: String,
        /// What happened, for example "world_started". It decides what
        /// the payload has to look like.
        pub kind: String,
        /// When it happened, in seconds since 1970 (UTC).
        pub time: i64,
        /// The details, depending on the kind.
        #[schema(value_type = Object)]
        pub payload: Value,
    }

    /// Several events in one request, oldest first.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
    pub struct EventBatch {
        pub events: Vec<Event>,
    }

    /// What the backend did with an event. In every case the world may
    /// forget the event: sending it again would change nothing.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum EventOutcome {
        /// Taken in.
        Accepted,
        /// Seen before, nothing was done again.
        Duplicate,
        /// The backend does not know this kind of event.
        Unknown,
        /// The payload does not fit the kind.
        Invalid,
    }

    /// The outcome for one event of a batch.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct EventResult {
        pub id: String,
        pub outcome: EventOutcome,
    }

    /// Answer to a batch: one result per event, in the same order.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct EventBatchResult {
        pub results: Vec<EventResult>,
    }

    /// Payload of the event "world_started".
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct WorldStarted {
        /// Version of the game engine, as it names itself.
        pub engine: String,
        /// Names of the mods that are loaded.
        pub mods: Vec<String>,
    }

    /// Something the backend wants a world to do.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
    pub struct Job {
        pub id: String,
        /// What to do, for example "ping". It decides what the payload has
        /// to look like.
        pub kind: String,
        #[schema(value_type = Object)]
        pub payload: Value,
    }

    /// The jobs that wait for a world. Empty if none came in time.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
    pub struct JobList {
        pub jobs: Vec<Job>,
    }

    /// How a job went.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct JobResult {
        pub ok: bool,
        /// A short note, for example why it failed.
        #[serde(default)]
        pub message: String,
    }

    /// Answer to a request that needs nothing said.
    #[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Done {}
}

/// Answer to a request that failed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ApiError {
    /// What went wrong, for people.
    pub error: String,
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
