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

/// Answer of the health check. Everybody may ask, so it says nothing
/// but whether the backend can do its work.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct Health {
    pub status: HealthStatus,
}

impl Health {
    /// Builds the answer from the one thing that can be missing so far.
    pub fn new(database: bool) -> Self {
        Self {
            status: if database {
                HealthStatus::Ok
            } else {
                HealthStatus::Degraded
            },
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
    /// Kind of the event that lists the accounts that may have web access.
    pub const EVENT_TEACHERS: &str = "teachers";
    /// Kind of the event that carries what a teacher did with their web
    /// access at the desk.
    pub const EVENT_WEB_ACCESS: &str = "web_access";
    /// Kind of the event that says which accounts a world has created.
    pub const EVENT_ACCOUNTS_CREATED: &str = "accounts_created";
    /// Kind of the event that carries the display name of one account.
    pub const EVENT_DISPLAY_NAME: &str = "display_name";
    /// Kind of the job that only checks the way to the world and back.
    pub const JOB_PING: &str = "ping";
    /// Kind of the job that makes a world send its whole state again.
    pub const JOB_SYNC_STATE: &str = "sync_state";

    /// Kind of the job that tells a world how the web access of a teacher
    /// stands.
    pub const JOB_WEB_ACCESS_STATUS: &str = "web_access_status";

    /// Kind of the job that makes a world create accounts for students.
    pub const JOB_CREATE_ACCOUNTS: &str = "create_accounts";

    /// Kind of the job that makes a world set a new start password for an
    /// account.
    pub const JOB_SET_PASSWORD: &str = "set_password";

    /// Kind of the job that makes a world take the display name of a
    /// student away.
    pub const JOB_REMOVE_DISPLAY_NAME: &str = "remove_display_name";

    /// Kind of the job that makes a world lock or unlock choosing a
    /// display name for a student.
    pub const JOB_SET_DISPLAY_LOCKED: &str = "set_display_locked";

    /// Kind of the job that makes a world delete all its protocols: the
    /// end of the year.
    pub const JOB_CLEAR_PROTOCOLS: &str = "clear_protocols";

    /// Kind of the job that makes a world set the level of a student in
    /// a module.
    pub const JOB_SET_LEVEL: &str = "set_level";

    /// Kind of the job that makes a world lock or unlock moving up for a
    /// student in a module.
    pub const JOB_SET_LOCKED: &str = "set_locked";

    /// The protocols a world keeps. Their entries are deleted with the end
    /// of the school year.
    pub const PROTOCOLS: [&str; 5] = ["rewards", "chat", "signs", "desk", "names"];

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

    /// Payload of the event "teachers": the accounts that hold the
    /// privilege for web access in this world. It replaces what the
    /// backend knew before.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Teachers {
        #[serde(default, deserialize_with = "null_as_default")]
        pub accounts: Vec<String>,
        /// The accounts that hold the privilege of the school
        /// administration in this world.
        #[serde(default, deserialize_with = "null_as_default")]
        pub school_admins: Vec<String>,
    }

    /// What a teacher can do with their web access at the desk.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum WebAccessAction {
        /// Enter an address or change it. The address is in `email`.
        Set,
        /// Send the confirmation mail again.
        Resend,
        /// Remove the web access with its address.
        Remove,
    }

    /// Payload of the event "web_access": what a teacher did with their
    /// web access.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct WebAccessRequest {
        /// Account name of the teacher.
        pub account: String,
        pub action: WebAccessAction,
        /// The address, for the action "set" only.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub email: Option<String>,
    }

    /// Payload of the job "web_access_status": how the web access of a
    /// teacher stands. Addresses are shortened, the world never gets a
    /// whole one back.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct WebAccessStatus {
        /// Account name of the teacher.
        pub account: String,
        /// The confirmed address, shortened. Missing without one.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub address: Option<String>,
        /// The address that waits for its confirmation, shortened.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub pending: Option<String>,
    }

    /// An account a world shall create.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct NewAccount {
        pub name: String,
        /// The start password. The world stores only its hash.
        pub password: String,
    }

    /// Payload of the job "create_accounts".
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct CreateAccounts {
        pub accounts: Vec<NewAccount>,
    }

    /// Payload of the job "set_password". A world sets the password only
    /// for an ordinary account: one that holds nothing but what every new
    /// player gets.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct SetPassword {
        pub name: String,
        /// The new start password. The world stores only its hash.
        pub password: String,
    }

    /// Payload of the event "display_name": what an account is shown
    /// under in the world. Always the whole state of the account.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct DisplayName {
        pub account: String,
        /// The name the player chose. Missing or null while the account
        /// name is shown.
        #[serde(default)]
        pub name: Option<String>,
        /// When the player chose a name last, in seconds since 1970.
        /// Missing or null if never, or after a teacher took it away.
        #[serde(default)]
        pub changed_at: Option<i64>,
        /// True if a teacher has locked choosing a name.
        #[serde(default)]
        pub locked: bool,
    }

    /// Payload of the job "remove_display_name". The world writes it
    /// into the protocol of the names, under the account of the teacher.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct RemoveDisplayName {
        /// Account name of the student.
        pub account: String,
        /// Account name of the teacher who ordered it.
        pub by: String,
    }

    /// Payload of the job "set_display_locked". The world writes it into
    /// the protocol of the names, under the account of the teacher.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct SetDisplayLocked {
        /// Account name of the student.
        pub account: String,
        /// True to lock choosing a name, false to unlock it.
        pub locked: bool,
        /// Account name of the teacher who ordered it.
        pub by: String,
    }

    /// Payload of the job "clear_protocols".
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ClearProtocols {
        /// Account name of who closed the year, for the log of the world.
        pub by: String,
    }

    /// Payload of the job "set_level". The world writes the change into
    /// the protocol of the desk, under the account of the teacher.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct SetLevel {
        /// Account name of the student.
        pub account: String,
        pub module: String,
        /// The new level, counted from 1.
        pub level: u32,
        /// Account name of the teacher who ordered it.
        pub by: String,
    }

    /// Payload of the job "set_locked". The world writes the change into
    /// the protocol of the desk, under the account of the teacher.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct SetLocked {
        /// Account name of the student.
        pub account: String,
        pub module: String,
        /// True to lock moving up after a completed level, false to
        /// unlock it.
        pub locked: bool,
        /// Account name of the teacher who ordered it.
        pub by: String,
    }

    /// Payload of the event "accounts_created": what became of the
    /// accounts a world was asked to create.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct AccountsCreated {
        /// Names of the accounts that exist now, with the start password.
        #[serde(default, deserialize_with = "null_as_default")]
        pub created: Vec<String>,
        /// Names that were refused: taken by somebody else in this world,
        /// or not a name the engine accepts. Nothing was changed for them.
        #[serde(default, deserialize_with = "null_as_default")]
        pub refused: Vec<String>,
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

/// Interface for the browser: what the frontend and the backend say to
/// each other.
pub mod web {
    use serde::{Deserialize, Serialize};
    use utoipa::ToSchema;

    /// Request to confirm an address with the token from a mail.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ConfirmRequest {
        pub token: String,
    }

    /// Request for a mail with a link that logs in.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct LoginLinkRequest {
        /// The confirmed address of the teacher.
        pub email: String,
    }

    /// Request to log in with the token from a mail.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct LoginRequest {
        pub token: String,
    }

    /// The teacher who is logged in.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Me {
        /// Account name of the teacher.
        pub account: String,
        /// The confirmed address of the teacher.
        pub email: String,
        /// Names of the worlds in which the teacher holds the privilege
        /// for web access.
        pub worlds: Vec<String>,
        /// When the session ends, in seconds since 1970 (UTC).
        pub expires_at: i64,
        /// True if the teacher belongs to the school administration:
        /// they see every group and assign teachers to groups.
        pub school_admin: bool,
    }

    /// A group. It is the home of one world, one to one.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Group {
        /// Fixed identifier of the group and its world.
        pub id: String,
        /// Name for people. It can be changed.
        pub name: String,
        /// Account names of the teachers who are assigned to the group,
        /// sorted.
        pub teachers: Vec<String>,
        /// When the world of the group last called, in seconds since
        /// 1970 (UTC). Missing if it never did.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub last_seen_at: Option<i64>,
        /// Where players reach the world, for example
        /// `spiel.schule.example, Port 30000`. It is printed on the
        /// access slips. Missing until somebody entered it.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub address: Option<String>,
    }

    /// How far the account of a student is.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum StudentState {
        /// A name that was rolled. Nothing exists in the world yet, and
        /// the name can still be rolled again.
        Draft,
        /// The world was asked to create the account and has not
        /// answered yet.
        Creating,
        /// The account exists in the world.
        Active,
        /// The world refused the name. The account does not exist.
        Refused,
    }

    /// How far a new start password for an account is.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum PasswordState {
        /// The world was asked to set it and has not answered yet. Until
        /// then the old password counts.
        Pending,
        /// The world refused to set it. The old password counts.
        Refused,
    }

    /// The account of a student.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Student {
        /// Account name. It says nothing about the person.
        pub account: String,
        pub state: StudentState,
        /// Missing in the usual case: the password the student was given
        /// last is the one that counts.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub password: Option<PasswordState>,
        /// The name the student chose to be shown under in the world.
        /// Missing while the account name is shown.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub display_name: Option<String>,
        /// When the student chose that name, in seconds since 1970.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub display_changed_at: Option<i64>,
        /// True if a teacher has locked choosing a name.
        #[serde(default)]
        pub display_locked: bool,
        /// Missing in the usual case: no change to the display name or
        /// its lock is on its way.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub display_change: Option<ChangeState>,
    }

    /// The word a request to close the year has to carry, so that no
    /// request does it by accident.
    pub const YEAR_END_CONFIRMATION: &str = "close-the-year";

    /// Request to close the year.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct YearEndRequest {
        /// Has to be "close-the-year".
        pub confirm: String,
    }

    /// A year that was closed. Kept for good, without any content.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct YearEndRun {
        /// When, in seconds since 1970.
        pub time: i64,
        /// Account name of who did it.
        pub account: String,
        /// How many groups there were.
        pub groups: i64,
        /// How many entries of protocols the backend deleted.
        pub protocol_entries: i64,
        /// How many entries of the list of exports it deleted.
        pub exports: i64,
    }

    /// What closing the year would delete for one group, and how far its
    /// world is with the last one.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct YearEndGroup {
        pub id: String,
        pub name: String,
        /// Entries of protocols the backend holds for the group.
        pub protocol_entries: i64,
        /// Entries of the list of exports.
        pub exports: i64,
        /// Missing if the world was never asked to delete its protocols,
        /// or has done so. Pending: it has not answered yet, for example
        /// because it does not run. Refused: it could not.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub world: Option<ChangeState>,
    }

    /// What closing the year would delete, and when it was closed last.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct YearEnd {
        pub groups: Vec<YearEndGroup>,
        /// The years that were closed, newest first.
        pub runs: Vec<YearEndRun>,
    }

    /// One entry of a protocol of a world.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ProtocolRow {
        /// Number of the entry in the backend. Entries that arrived
        /// later have a larger one.
        pub id: i64,
        /// When it happened in the world, in seconds since 1970.
        pub time: i64,
        /// Account name of who did it.
        pub account: String,
        /// The display name the account has now. Protocols only keep
        /// the account name.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub display_name: Option<String>,
        /// The other columns of the entry.
        pub fields: std::collections::BTreeMap<String, String>,
    }

    /// A part of a protocol, newest entries first.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ProtocolPage {
        /// The columns of this protocol besides time and account, in the
        /// order to show them.
        pub columns: Vec<String>,
        pub entries: Vec<ProtocolRow>,
        /// True if there are older entries than the last one here. Ask
        /// for them with `before` set to its id.
        pub more: bool,
    }

    /// A part of a group that changed. The way
    /// `/api/web/v1/groups/{id}/changes` sends it as the data of an event
    /// named "change"; a page then loads that part again.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum ChangeTopic {
        /// Name, teachers or address of the group.
        Group,
        /// The list of students: accounts, passwords on their way,
        /// display names.
        Students,
        /// Levels, workload, locks and trophies.
        Progress,
        /// New entries in a protocol.
        Protocols,
    }

    impl ChangeTopic {
        /// The word the topic is sent as.
        pub fn as_str(self) -> &'static str {
            match self {
                Self::Group => "group",
                Self::Students => "students",
                Self::Progress => "progress",
                Self::Protocols => "protocols",
            }
        }
    }

    /// Request to lock or unlock choosing a display name.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct DisplayLock {
        pub locked: bool,
    }

    /// One entry of the history of the display names of a student.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct DisplayNameEntry {
        /// When it happened, in seconds since 1970.
        pub time: i64,
        /// What happened.
        pub action: DisplayNameAction,
        /// The name that was chosen, given up or taken away. Missing for
        /// a lock.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub name: Option<String>,
        /// Account name of who did it: the student, or a teacher.
        pub by: String,
    }

    /// What can happen to a display name.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum DisplayNameAction {
        /// The student chose the name.
        Chosen,
        /// The student went back to the account name.
        GivenUp,
        /// A teacher took the name away.
        Removed,
        /// A teacher locked choosing a name.
        Locked,
        /// A teacher unlocked choosing a name.
        Unlocked,
    }

    /// The history of the display names of a student, newest first. It
    /// comes from a protocol of the world and is deleted with it.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct DisplayNameHistory {
        pub entries: Vec<DisplayNameEntry>,
    }

    /// The accounts of the students of a group, in the order they were
    /// rolled. A name that is rolled again keeps its place.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Students {
        pub students: Vec<Student>,
    }

    /// Request to roll names for new accounts.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct DraftRequest {
        /// How many names to roll.
        pub count: u32,
    }

    /// What a student needs to log in for the first time.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct AccessSlip {
        pub account: String,
        /// The start password. The backend shows it this once and does
        /// not keep it.
        pub password: String,
    }

    /// Answer to creating accounts: the slips to print.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct AccessSlips {
        pub slips: Vec<AccessSlip>,
    }

    /// A learning module of the world of a group.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ProgressModule {
        pub id: String,
        /// Name for people, in the language of the world.
        pub title: String,
        /// How many levels the module has.
        pub levels: u32,
    }

    /// How far a student is with one kind of task of their level.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ProgressTask {
        /// Name for people, in the language of the world.
        pub title: String,
        pub solved: u32,
        pub required: u32,
    }

    /// How far a change a teacher ordered is.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum ChangeState {
        /// The world was asked and has not answered yet. What is shown
        /// is still the old state.
        Pending,
        /// The world refused the newest change. Nothing was changed.
        Refused,
    }

    /// Where a student stands in one module.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ModuleProgress {
        /// Id of the module.
        pub module: String,
        /// False if the world has reported nothing yet: the student
        /// stands at the start of level 1.
        pub started: bool,
        /// Current level, counted from 1.
        pub level: u32,
        /// True if moving up after a completed level is locked.
        pub locked: bool,
        /// Share of the workload of the level that is done, 0 to 100.
        pub percent: u32,
        /// True if the whole module is completed.
        pub completed: bool,
        /// The kinds of tasks of the current level.
        pub tasks: Vec<ProgressTask>,
        /// Missing in the usual case: no change is on its way.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub change: Option<ChangeState>,
    }

    /// A trophy a student has earned.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct EarnedTrophy {
        /// Name for people, in the language of the world.
        pub title: String,
        /// "bronze", "silver" or "gold".
        pub material: String,
    }

    /// Where a student stands: one entry per module of the world, in the
    /// order of the modules, and the trophies.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct StudentProgress {
        pub account: String,
        /// The name the student chose to be shown under in the world.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub display_name: Option<String>,
        pub modules: Vec<ModuleProgress>,
        pub trophies: Vec<EarnedTrophy>,
    }

    /// The progress of a group: the modules of its world and the
    /// students whose accounts exist, in the order of the list of
    /// students.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct GroupProgress {
        pub modules: Vec<ProgressModule>,
        pub students: Vec<StudentProgress>,
    }

    /// Request to change where a student stands in a module. At least
    /// one of the two has to be there.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct ProgressChange {
        /// The new level, if it changes.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub level: Option<u32>,
        /// Whether moving up is locked from now on, if that changes.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub locked: Option<bool>,
    }

    /// The groups a teacher may see.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Groups {
        pub groups: Vec<Group>,
    }

    /// Request to change a group.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct GroupChange {
        /// The new name, if it changes.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub name: Option<String>,
        /// The teachers of the group from now on, if they change. The
        /// list replaces the old one.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub teachers: Option<Vec<String>>,
        /// Where players reach the world, if it changes. An empty text
        /// removes it.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub address: Option<String>,
    }

    /// The accounts that can be assigned to groups: everybody who holds
    /// the privilege for web access in some world. Sorted.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct TeacherList {
        pub teachers: Vec<String>,
    }

    /// How mails leave the backend.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum MailTransport {
        /// Through a mail server.
        Smtp,
        /// Not at all: they are written to the terminal of the backend.
        Terminal,
    }

    /// State of the backend with its details, for teachers who are
    /// logged in.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Status {
        pub status: crate::HealthStatus,
        /// Version of the backend, as in its package.
        pub version: String,
        pub mail: MailTransport,
    }

    /// Answer to a confirmed address.
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
    pub struct Confirmed {
        /// Account name of the teacher the address now belongs to.
        pub account: String,
    }
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
    /// The teacher is logged in, but may not do this.
    Forbidden,
    /// Another group already has this name.
    NameTaken,
    /// No free account name turned up.
    NoNames,
    /// The link from a mail is unknown, used or too old.
    InvalidToken,
    /// The address already belongs to another account.
    AddressTaken,
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
    fn health_says_only_whether_the_backend_can_work() {
        assert_eq!(Health::new(true).status, HealthStatus::Ok);
        assert_eq!(Health::new(false).status, HealthStatus::Degraded);
        assert_eq!(
            serde_json::to_string(&Health::new(true)).unwrap(),
            r#"{"status":"ok"}"#
        );
    }
}
