//! Jobs for the worlds: putting them in, handing them out and noting how
//! they went.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use lep_protocol::world::{Job, JobResult};
use serde_json::Value;
use sqlx::{Row, SqlitePool};
use tokio::sync::Notify;
use uuid::Uuid;

use crate::clock;

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
    let id = Uuid::new_v4().to_string();
    sqlx::query(
        "INSERT INTO jobs (id, world_id, kind, payload, created_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(world_id)
    .bind(kind)
    .bind(payload.to_string())
    .bind(clock::now())
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
         WHERE world_id = ? AND finished_at IS NULL ORDER BY created_at, rowid",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    if rows.is_empty() {
        return Ok(Vec::new());
    }
    sqlx::query(
        "UPDATE jobs SET delivered_at = ?
         WHERE world_id = ? AND finished_at IS NULL AND delivered_at IS NULL",
    )
    .bind(clock::now())
    .bind(world_id)
    .execute(pool)
    .await?;
    Ok(rows
        .iter()
        .map(|row| Job {
            id: row.get("id"),
            kind: row.get("kind"),
            payload: serde_json::from_str(row.get("payload")).unwrap_or(Value::Null),
        })
        .collect())
}

/// Notes how a job went. Returns false if the world has no such job. A
/// second result for the same job changes nothing.
pub async fn finish(
    pool: &SqlitePool,
    world_id: &str,
    job_id: &str,
    result: &JobResult,
) -> Result<bool> {
    let known: Option<i64> = sqlx::query_scalar("SELECT 1 FROM jobs WHERE id = ? AND world_id = ?")
        .bind(job_id)
        .bind(world_id)
        .fetch_optional(pool)
        .await?;
    if known.is_none() {
        return Ok(false);
    }
    // A job that carried passwords forgets them here: once the world has
    // answered, nobody needs them in the database any more.
    sqlx::query(
        "UPDATE jobs SET finished_at = ?, ok = ?, message = ?,
            payload = CASE WHEN kind = 'create_accounts' THEN '{}' ELSE payload END
         WHERE id = ? AND world_id = ? AND finished_at IS NULL",
    )
    .bind(clock::now())
    .bind(result.ok)
    .bind(&result.message)
    .bind(job_id)
    .bind(world_id)
    .execute(pool)
    .await?;
    Ok(true)
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
