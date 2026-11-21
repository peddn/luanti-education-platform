//! Jobs for the worlds and for the agent: putting them in, handing them
//! out and noting how they went. Both go through the same queue. Every
//! job names who is to do it, and each side only ever gets its own.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use lep_protocol::world::{Job, JobResult};
use serde_json::Value;
use sqlx::{Row, SqlitePool};
use tokio::sync::Notify;
use uuid::Uuid;

use crate::clock;

/// Who is to do a job that concerns a world: the world itself.
const WORLD: &str = "world";
/// Who is to do a job that concerns a world: the agent that runs it.
const AGENT: &str = "agent";
/// Name of the bell the agent listens to. Worlds have their id as name,
/// which never looks like this.
pub const AGENT_BELL: &str = "agent";

/// Wakes the requests of worlds that wait for a job. A request that waits
/// is told at once when a job for its world comes in.
#[derive(Clone, Default)]
pub struct Waiters {
    by_world: Arc<Mutex<HashMap<String, Arc<Notify>>>>,
}

impl Waiters {
    /// Returns the bell of a world: whoever waits for jobs listens to it.
    pub fn of(&self, world_id: &str) -> Arc<Notify> {
        let mut by_world = self.by_world.lock().expect("the list of waiters is broken");
        by_world.entry(world_id.to_owned()).or_default().clone()
    }

    /// Rings the bell of a world.
    pub fn wake(&self, world_id: &str) {
        self.of(world_id).notify_waiters();
    }
}

/// Puts a job for a world into the database and returns its id.
pub async fn add(pool: &SqlitePool, world_id: &str, kind: &str, payload: &Value) -> Result<String> {
    add_about(pool, world_id, kind, payload, None).await
}

/// Puts a job into the database that is about one account, and returns
/// its id. The account stays known after the job has forgotten its
/// payload.
pub async fn add_about(
    pool: &SqlitePool,
    world_id: &str,
    kind: &str,
    payload: &Value,
    subject: Option<&str>,
) -> Result<String> {
    insert(pool, WORLD, world_id, kind, payload, subject).await
}

/// Puts a job for the agent into the database and returns its id. The
/// job is about one world.
pub async fn add_for_agent(
    pool: &SqlitePool,
    world_id: &str,
    kind: &str,
    payload: &Value,
) -> Result<String> {
    insert(pool, AGENT, world_id, kind, payload, None).await
}

async fn insert(
    pool: &SqlitePool,
    recipient: &str,
    world_id: &str,
    kind: &str,
    payload: &Value,
    subject: Option<&str>,
) -> Result<String> {
    let id = Uuid::new_v4().to_string();
    sqlx::query(
        "INSERT INTO jobs (id, world_id, kind, payload, created_at, subject, recipient)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(world_id)
    .bind(kind)
    .bind(payload.to_string())
    .bind(clock::now())
    .bind(subject)
    .bind(recipient)
    .execute(pool)
    .await?;
    Ok(id)
}

/// Returns the jobs of a world that are not finished, oldest first, and
/// notes that they were handed out. A job is handed out again until the
/// world reports its result, so no job is lost when a connection breaks.
pub async fn take_waiting(pool: &SqlitePool, world_id: &str) -> Result<Vec<Job>> {
    let rows = sqlx::query(
        "SELECT id, kind, payload FROM jobs
         WHERE recipient = 'world' AND world_id = ? AND finished_at IS NULL
         ORDER BY created_at, rowid",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    if rows.is_empty() {
        return Ok(Vec::new());
    }
    sqlx::query(
        "UPDATE jobs SET delivered_at = ?
         WHERE recipient = 'world' AND world_id = ?
           AND finished_at IS NULL AND delivered_at IS NULL",
    )
    .bind(clock::now())
    .bind(world_id)
    .execute(pool)
    .await?;
    Ok(rows.iter().map(job_from_row).collect())
}

/// Returns the jobs for the agent that are not finished, oldest first,
/// and notes that they were handed out. Like the jobs of a world, they
/// are handed out again until their result is reported.
pub async fn take_waiting_for_agent(pool: &SqlitePool) -> Result<Vec<Job>> {
    let rows = sqlx::query(
        "SELECT id, kind, payload FROM jobs
         WHERE recipient = 'agent' AND finished_at IS NULL ORDER BY created_at, rowid",
    )
    .fetch_all(pool)
    .await?;
    if rows.is_empty() {
        return Ok(Vec::new());
    }
    sqlx::query(
        "UPDATE jobs SET delivered_at = ?
         WHERE recipient = 'agent' AND finished_at IS NULL AND delivered_at IS NULL",
    )
    .bind(clock::now())
    .execute(pool)
    .await?;
    Ok(rows.iter().map(job_from_row).collect())
}

fn job_from_row(row: &sqlx::sqlite::SqliteRow) -> Job {
    Job {
        id: row.get("id"),
        kind: row.get("kind"),
        payload: serde_json::from_str(row.get("payload")).unwrap_or(Value::Null),
    }
}

/// Notes how a job went. Returns false if the world has no such job. A
/// second result for the same job changes nothing.
pub async fn finish(
    pool: &SqlitePool,
    world_id: &str,
    job_id: &str,
    result: &JobResult,
) -> Result<bool> {
    let known: Option<i64> = sqlx::query_scalar(
        "SELECT 1 FROM jobs WHERE id = ? AND world_id = ? AND recipient = 'world'",
    )
    .bind(job_id)
    .bind(world_id)
    .fetch_optional(pool)
    .await?;
    if known.is_none() {
        return Ok(false);
    }
    note_result(pool, job_id, result).await?;
    Ok(true)
}

/// Notes how a job for the agent went. Returns the id of the world it
/// was about, or `None` if the agent has no such job. A second result
/// for the same job changes nothing.
pub async fn finish_for_agent(
    pool: &SqlitePool,
    job_id: &str,
    result: &JobResult,
) -> Result<Option<String>> {
    let world: Option<String> =
        sqlx::query_scalar("SELECT world_id FROM jobs WHERE id = ? AND recipient = 'agent'")
            .bind(job_id)
            .fetch_optional(pool)
            .await?;
    if world.is_some() {
        note_result(pool, job_id, result).await?;
    }
    Ok(world)
}

async fn note_result(pool: &SqlitePool, job_id: &str, result: &JobResult) -> Result<()> {
    // A job that carried passwords or keys forgets them here: once it is
    // answered, nobody needs them in the database any more.
    sqlx::query(
        "UPDATE jobs SET finished_at = ?, ok = ?, message = ?,
            payload = CASE
                WHEN kind IN ('create_accounts', 'set_password', 'set_password_entry',
                              'create_world') THEN '{}'
                ELSE payload END
         WHERE id = ? AND finished_at IS NULL",
    )
    .bind(clock::now())
    .bind(result.ok)
    .bind(&result.message)
    .bind(job_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// How the newest job of one kind for the agent about a world stands.
pub async fn last_for_agent(
    pool: &SqlitePool,
    world_id: &str,
    kind: &str,
) -> Result<Option<JobState>> {
    let id: Option<String> = sqlx::query_scalar(
        "SELECT id FROM jobs WHERE recipient = 'agent' AND world_id = ? AND kind = ?
         ORDER BY created_at DESC, rowid DESC LIMIT 1",
    )
    .bind(world_id)
    .bind(kind)
    .fetch_optional(pool)
    .await?;
    match id {
        Some(id) => state(pool, &id).await,
        None => Ok(None),
    }
}

/// How a job stands, for people who look after the backend.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JobState {
    pub delivered: bool,
    pub finished: bool,
    pub ok: Option<bool>,
    pub message: Option<String>,
}

pub async fn state(pool: &SqlitePool, job_id: &str) -> Result<Option<JobState>> {
    let row = sqlx::query("SELECT delivered_at, finished_at, ok, message FROM jobs WHERE id = ?")
        .bind(job_id)
        .fetch_optional(pool)
        .await?;
    Ok(row.map(|row| JobState {
        delivered: row.get::<Option<i64>, _>("delivered_at").is_some(),
        finished: row.get::<Option<i64>, _>("finished_at").is_some(),
        ok: row.get::<Option<bool>, _>("ok"),
        message: row.get("message"),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, worlds};
    use serde_json::json;

    async fn setup() -> (SqlitePool, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        (pool, world.id)
    }

    #[tokio::test]
    async fn hands_out_jobs_until_they_are_finished() {
        let (pool, world) = setup().await;
        assert!(take_waiting(&pool, &world).await.unwrap().is_empty());

        let first = add(&pool, &world, "ping", &json!({})).await.unwrap();
        let second = add(&pool, &world, "ping", &json!({ "n": 2 }))
            .await
            .unwrap();

        let jobs = take_waiting(&pool, &world).await.unwrap();
        assert_eq!(jobs.len(), 2);
        assert_eq!(jobs[0].id, first);
        assert_eq!(jobs[1].payload, json!({ "n": 2 }));
        assert!(state(&pool, &first).await.unwrap().unwrap().delivered);

        // Not finished yet: handed out again.
        assert_eq!(take_waiting(&pool, &world).await.unwrap().len(), 2);

        let result = JobResult {
            ok: true,
            message: "pong".to_owned(),
        };
        assert!(finish(&pool, &world, &first, &result).await.unwrap());
        let jobs = take_waiting(&pool, &world).await.unwrap();
        assert_eq!(jobs.len(), 1);
        assert_eq!(jobs[0].id, second);

        let done = state(&pool, &first).await.unwrap().unwrap();
        assert!(done.finished);
        assert_eq!(done.ok, Some(true));
        assert_eq!(done.message.as_deref(), Some("pong"));
    }

    #[tokio::test]
    async fn keeps_the_first_result_of_a_job() {
        let (pool, world) = setup().await;
        let job = add(&pool, &world, "ping", &json!({})).await.unwrap();
        let good = JobResult {
            ok: true,
            message: "pong".to_owned(),
        };
        let bad = JobResult {
            ok: false,
            message: "late".to_owned(),
        };
        assert!(finish(&pool, &world, &job, &good).await.unwrap());
        assert!(finish(&pool, &world, &job, &bad).await.unwrap());
        assert_eq!(state(&pool, &job).await.unwrap().unwrap().ok, Some(true));
    }

    #[tokio::test]
    async fn a_world_sees_and_finishes_only_its_own_jobs() {
        let (pool, world) = setup().await;
        let (other, _) = worlds::add(&pool, "8a").await.unwrap();
        let job = add(&pool, &world, "ping", &json!({})).await.unwrap();

        assert!(take_waiting(&pool, &other.id).await.unwrap().is_empty());
        let result = JobResult {
            ok: true,
            message: String::new(),
        };
        assert!(!finish(&pool, &other.id, &job, &result).await.unwrap());
        assert!(!finish(&pool, &world, "no-such-job", &result).await.unwrap());
        assert!(!state(&pool, &job).await.unwrap().unwrap().finished);
    }

    #[tokio::test]
    async fn worlds_and_agent_only_get_their_own_jobs() {
        let (pool, world) = setup().await;
        let for_world = add(&pool, &world, "ping", &json!({})).await.unwrap();
        let payload = json!({ "world": world, "bridge_key": "lepw_secret" });
        let for_agent = add_for_agent(&pool, &world, "create_world", &payload)
            .await
            .unwrap();

        let of_world = take_waiting(&pool, &world).await.unwrap();
        assert_eq!(of_world.len(), 1);
        assert_eq!(of_world[0].id, for_world);
        let of_agent = take_waiting_for_agent(&pool).await.unwrap();
        assert_eq!(of_agent.len(), 1);
        assert_eq!(of_agent[0].id, for_agent);
        assert_eq!(of_agent[0].payload["bridge_key"], "lepw_secret");

        // Neither can answer for the other.
        let result = JobResult {
            ok: true,
            message: String::new(),
        };
        assert!(!finish(&pool, &world, &for_agent, &result).await.unwrap());
        assert_eq!(
            finish_for_agent(&pool, &for_world, &result).await.unwrap(),
            None
        );
        assert!(!state(&pool, &for_agent).await.unwrap().unwrap().finished);
        assert!(!state(&pool, &for_world).await.unwrap().unwrap().finished);
    }

    #[tokio::test]
    async fn a_finished_job_for_the_agent_forgets_its_key() {
        let (pool, world) = setup().await;
        assert_eq!(
            last_for_agent(&pool, &world, "create_world").await.unwrap(),
            None
        );
        let payload = json!({ "world": world, "bridge_key": "lepw_secret" });
        let job = add_for_agent(&pool, &world, "create_world", &payload)
            .await
            .unwrap();
        let waiting = last_for_agent(&pool, &world, "create_world")
            .await
            .unwrap()
            .unwrap();
        assert!(!waiting.finished);

        let result = JobResult {
            ok: false,
            message: "no port is free".to_owned(),
        };
        assert_eq!(
            finish_for_agent(&pool, &job, &result).await.unwrap(),
            Some(world.clone())
        );
        assert!(take_waiting_for_agent(&pool).await.unwrap().is_empty());
        let stored: String = sqlx::query_scalar("SELECT payload FROM jobs WHERE id = ?")
            .bind(&job)
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(stored, "{}");
        let refused = last_for_agent(&pool, &world, "create_world")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(refused.ok, Some(false));
        assert_eq!(refused.message.as_deref(), Some("no port is free"));
    }

    #[tokio::test]
    async fn waking_reaches_whoever_listens() {
        let waiters = Waiters::default();
        let bell = waiters.of("w1");
        let listening = tokio::spawn(async move { bell.notified().await });
        // Give the listener time to start listening.
        tokio::task::yield_now().await;
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        waiters.wake("w1");
        tokio::time::timeout(std::time::Duration::from_secs(1), listening)
            .await
            .expect("the listener was not woken")
            .unwrap();
    }
}
