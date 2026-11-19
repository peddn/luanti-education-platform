//! The end of the year: the one moment data is deleted on a large scale.
//! One switch for the whole school, see the concept, section 12.
//!
//! Deleted are the protocols: the copies here, the list of exports, and
//! through a job the files in every world. What a student has reached
//! stays. Archives and backups of worlds follow with the agent.

use anyhow::Result;
use lep_protocol::web::{ChangeState, YearEnd, YearEndGroup, YearEndRun};
use lep_protocol::world::{ClearProtocols, JOB_CLEAR_PROTOCOLS};
use sqlx::{Row, SqlitePool};

use crate::jobs;

/// Returns what closing the year would delete per group, how far the
/// worlds are with the last one, and the years that were closed.
pub async fn overview(pool: &SqlitePool) -> Result<YearEnd> {
    let rows = sqlx::query(
        "SELECT worlds.id, worlds.name,
                (SELECT COUNT(*) FROM protocol_entries
                 WHERE protocol_entries.world_id = worlds.id) AS protocol_entries,
                (SELECT COUNT(*) FROM exports WHERE exports.world_id = worlds.id) AS exports,
                (SELECT CASE WHEN jobs.finished_at IS NULL THEN 'pending'
                             WHEN jobs.ok = 0 THEN 'refused' END
                 FROM jobs
                 WHERE jobs.world_id = worlds.id AND jobs.kind = 'clear_protocols'
                 ORDER BY jobs.finished_at IS NULL DESC, jobs.rowid DESC LIMIT 1) AS world
         FROM worlds ORDER BY worlds.name COLLATE NOCASE",
    )
    .fetch_all(pool)
    .await?;
    let groups = rows
        .iter()
        .map(|row| YearEndGroup {
            id: row.get("id"),
            name: row.get("name"),
            protocol_entries: row.get("protocol_entries"),
            exports: row.get("exports"),
            world: match row.get::<Option<String>, _>("world").as_deref() {
                Some("pending") => Some(ChangeState::Pending),
                Some("refused") => Some(ChangeState::Refused),
                _ => None,
            },
        })
        .collect();
    let runs = sqlx::query(
        "SELECT time, account, groups, protocol_entries, exports FROM year_ends ORDER BY id DESC",
    )
    .fetch_all(pool)
    .await?
    .iter()
    .map(|row| YearEndRun {
        time: row.get("time"),
        account: row.get("account"),
        groups: row.get("groups"),
        protocol_entries: row.get("protocol_entries"),
        exports: row.get("exports"),
    })
    .collect();
    Ok(YearEnd { groups, runs })
}

/// Closes the year: deletes the protocols and the list of exports here,
/// orders every world to delete its own, and notes that it happened.
/// Returns the ids of all groups, so their worlds can be woken.
/// @param account Account name of who does it.
pub async fn close(pool: &SqlitePool, time: i64, account: &str) -> Result<Vec<String>> {
    let mut tx = pool.begin().await?;
    let worlds: Vec<String> = sqlx::query_scalar("SELECT id FROM worlds ORDER BY id")
        .fetch_all(&mut *tx)
        .await?;
    let protocol_entries = sqlx::query("DELETE FROM protocol_entries")
        .execute(&mut *tx)
        .await?
        .rows_affected();
    let exports = sqlx::query("DELETE FROM exports")
        .execute(&mut *tx)
        .await?
        .rows_affected();
    sqlx::query(
        "INSERT INTO year_ends (time, account, groups, protocol_entries, exports)
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(time)
    .bind(account)
    .bind(worlds.len() as i64)
    .bind(protocol_entries as i64)
    .bind(exports as i64)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    let payload = serde_json::to_value(ClearProtocols {
        by: account.to_owned(),
    })?;
    for world in &worlds {
        jobs::add(pool, world, JOB_CLEAR_PROTOCOLS, &payload).await?;
    }
    Ok(worlds)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocols::{self, Filter};
    use crate::{db, state, worlds};
    use lep_protocol::world::{JobResult, Progress, ProtocolEntry};

    async fn write(pool: &SqlitePool, world: &str, time: i64, text: &str) -> bool {
        let entry = ProtocolEntry {
            protocol: "chat".to_owned(),
            account: "klugeEule".to_owned(),
            fields: [("text".to_owned(), text.to_owned())].into(),
        };
        state::store_protocol_entry(pool, world, time, &entry)
            .await
            .unwrap()
    }

    async fn entries(pool: &SqlitePool) -> i64 {
        sqlx::query_scalar("SELECT COUNT(*) FROM protocol_entries")
            .fetch_one(pool)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn deletes_the_protocols_of_all_groups_and_keeps_what_was_reached() {
        let pool = db::open_in_memory().await.unwrap();
        let (first, _) = worlds::add(&pool, "7b").await.unwrap();
        let (second, _) = worlds::add(&pool, "8a").await.unwrap();
        write(&pool, &first.id, 100, "eins").await;
        write(&pool, &first.id, 200, "zwei").await;
        write(&pool, &second.id, 300, "drei").await;
        protocols::record_export(
            &pool,
            &first.id,
            400,
            "lehrer1",
            "chat",
            &Filter::default(),
            2,
        )
        .await
        .unwrap();
        let progress = Progress {
            account: "klugeEule".to_owned(),
            module: "lep_math:math".to_owned(),
            level: 3,
            locked: false,
            percent: 40,
            completed: false,
            tasks: Vec::new(),
        };
        state::store_progress(&pool, &first.id, 100, &progress)
            .await
            .unwrap();

        let before = overview(&pool).await.unwrap();
        assert!(before.runs.is_empty());
        let seen: Vec<_> = before
            .groups
            .iter()
            .map(|group| {
                (
                    group.name.as_str(),
                    group.protocol_entries,
                    group.exports,
                    group.world,
                )
            })
            .collect();
        assert_eq!(seen, [("7b", 2, 1, None), ("8a", 1, 0, None)]);

        let woken = close(&pool, 1000, "leitung").await.unwrap();
        assert_eq!(woken.len(), 2);
        assert_eq!(entries(&pool).await, 0);
        let level: u32 = sqlx::query_scalar("SELECT level FROM progress")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(level, 3);

        let after = overview(&pool).await.unwrap();
        assert_eq!(
            after.runs,
            [YearEndRun {
                time: 1000,
                account: "leitung".to_owned(),
                groups: 2,
                protocol_entries: 3,
                exports: 1
            }]
        );
        for group in &after.groups {
            assert_eq!((group.protocol_entries, group.exports), (0, 0));
            assert_eq!(group.world, Some(ChangeState::Pending));
        }

        // Every world is ordered to delete its own files.
        for (world, ok) in [(&first.id, true), (&second.id, false)] {
            let sent = jobs::take_waiting(&pool, world).await.unwrap();
            assert_eq!(sent.len(), 1);
            assert_eq!(sent[0].kind, JOB_CLEAR_PROTOCOLS);
            assert_eq!(sent[0].payload, serde_json::json!({ "by": "leitung" }));
            let result = JobResult {
                ok,
                message: String::new(),
            };
            jobs::finish(&pool, world, &sent[0].id, &result)
                .await
                .unwrap();
        }
        let done = overview(&pool).await.unwrap();
        assert_eq!(done.groups[0].world, None);
        assert_eq!(done.groups[1].world, Some(ChangeState::Refused));
    }

    #[tokio::test]
    async fn does_not_keep_what_a_world_reports_from_before_the_year_was_closed() {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        close(&pool, 1000, "leitung").await.unwrap();
        // Taken off the hands of the world, so it does not send it again.
        assert!(write(&pool, &world.id, 900, "alt").await);
        assert!(write(&pool, &world.id, 1000, "gerade noch alt").await);
        assert_eq!(entries(&pool).await, 0);
        assert!(write(&pool, &world.id, 1001, "neu").await);
        assert_eq!(entries(&pool).await, 1);

        // A second year: the newest end counts, both stay noted.
        close(&pool, 2000, "leitung").await.unwrap();
        assert!(write(&pool, &world.id, 1500, "dazwischen").await);
        assert_eq!(entries(&pool).await, 0);
        let years = overview(&pool).await.unwrap().runs;
        assert_eq!(years.len(), 2);
        assert_eq!((years[0].time, years[0].protocol_entries), (2000, 1));
        assert_eq!((years[1].time, years[1].protocol_entries), (1000, 0));
    }
}
