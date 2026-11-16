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
    /// Kind of the event that lists the learning modules of a world.
    pub const EVENT_MODULES: &str = "modules";
    /// Kind of the event that carries the progress of one student in one
    /// module.
    pub const EVENT_PROGRESS: &str = "progress";
    /// Kind of the event that carries the trophies of one student.
    pub const EVENT_TROPHIES: &str = "trophies";
    /// Kind of the event that carries one entry of a protocol.
    pub const EVENT_PROTOCOL: &str = "protocol";
    /// Kind of the job that only checks the way to the world and back.
    pub const JOB_PING: &str = "ping";
    /// Kind of the job that makes a world send its whole state again.
    pub const JOB_SYNC_STATE: &str = "sync_state";

    /// The protocols a world keeps. Their entries are deleted with the end
    /// of the school year.
    pub const PROTOCOLS: [&str; 4] = ["rewards", "chat", "signs", "desk"];

    /// Reads a list or a map that may arrive as `null`. A Lua table without
    /// entries cannot say what it is, so the worlds send `null` for it.
    fn null_as_default<'de, D, T>(deserializer: D) -> Result<T, D::Error>
    where
        D: serde::Deserializer<'de>,
        T: Deserialize<'de> + Default,
    {
        Ok(Option::<T>::deserialize(deserializer)?.unwrap_or_default())
    }

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

    /// A kind of task of a level, with how often it has to be solved.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct TaskType {
        pub id: String,
        /// Name for people, in the language of the world.
        pub title: String,
        pub required: u32,
    }

    /// One level of a module: its workload.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Level {
        /// True if completing this level ends a stage of the module.
        pub stage: bool,
        #[serde(default, deserialize_with = "null_as_default")]
        pub tasks: Vec<TaskType>,
    }

    /// A learning module as a world knows it.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Module {
        pub id: String,
        /// Name for people, in the language of the world.
        pub title: String,
        #[serde(default, deserialize_with = "null_as_default")]
        pub levels: Vec<Level>,
    }

    /// Payload of the event "modules": all modules of the world. It
    /// replaces what the backend knew before.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Modules {
        #[serde(default, deserialize_with = "null_as_default")]
        pub modules: Vec<Module>,
    }

    /// How far a student is with one kind of task of their level.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct TaskProgress {
        pub id: String,
        pub solved: u32,
        pub required: u32,
    }

    /// Payload of the event "progress": where one student stands in one
    /// module. It is the whole state, not a change, and replaces what the
    /// backend knew before.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Progress {
        /// Account name of the student.
        pub account: String,
        pub module: String,
        /// Current level, counted from 1.
        pub level: u32,
        /// True if moving up after a completed level is locked.
        pub locked: bool,
        /// Share of the workload of the level that is done, 0 to 100.
        pub percent: u32,
        /// True if the whole module is completed.
        pub completed: bool,
        /// The kinds of tasks of the current level.
        #[serde(default, deserialize_with = "null_as_default")]
        pub tasks: Vec<TaskProgress>,
    }

    /// A trophy a student has earned.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Trophy {
        pub id: String,
        /// Name for people, in the language of the world.
        pub title: String,
        /// "bronze", "silver" or "gold".
        pub material: String,
    }

    /// Payload of the event "trophies": all trophies of one student. It
    /// replaces what the backend knew before.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Trophies {
        pub account: String,
        #[serde(default, deserialize_with = "null_as_default")]
        pub trophies: Vec<Trophy>,
    }

    /// Payload of the event "protocol": one entry of one of the protocols
    /// of a world. The time is the time of the event.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ProtocolEntry {
        /// Which protocol, one of `PROTOCOLS`.
        pub protocol: String,
        /// Account name of the player the entry is about. Never a display
        /// name.
        pub account: String,
        /// The other columns of the entry, by name.
        #[serde(default, deserialize_with = "null_as_default")]
        pub fields: std::collections::BTreeMap<String, String>,
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

/// Why a request failed, as a fixed word. The frontend translates it into
/// the language of the user.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    /// The caller did not prove who they are, or may not do this.
    Unauthorized,
    /// What was asked for does not exist.
    NotFound,
    /// The request carries more than is allowed.
    TooLarge,
    /// The request cannot be understood.
    InvalidRequest,
    /// The backend failed. The details are in its log.
    Internal,
}

/// Answer to a request that failed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ApiError {
    pub code: ErrorCode,
    /// What went wrong, in English, for logs and developers. It is not
    /// shown to users.
    pub message: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_list_may_arrive_as_null() {
        let progress: world::Progress = serde_json::from_str(
            r#"{"account":"anna","module":"m","level":1,"locked":false,
                "percent":0,"completed":false,"tasks":null}"#,
        )
        .unwrap();
        assert!(progress.tasks.is_empty());

        let trophies: world::Trophies = serde_json::from_str(r#"{"account":"anna"}"#).unwrap();
        assert!(trophies.trophies.is_empty());

        let modules: world::Modules = serde_json::from_str(r#"{"modules":null}"#).unwrap();
        assert!(modules.modules.is_empty());
    }

    #[test]
    fn a_protocol_entry_keeps_its_columns() {
        let entry: world::ProtocolEntry = serde_json::from_str(
            r#"{"protocol":"chat","account":"anna","fields":{"kind":"chat","text":"hi"}}"#,
        )
        .unwrap();
        assert_eq!(entry.fields["text"], "hi");

        let bare: world::ProtocolEntry =
            serde_json::from_str(r#"{"protocol":"desk","account":"anna","fields":null}"#).unwrap();
        assert!(bare.fields.is_empty());
        assert!(world::PROTOCOLS.contains(&entry.protocol.as_str()));
    }

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
