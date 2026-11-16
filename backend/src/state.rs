//! What the worlds report about their students: modules, progress,
//! trophies and protocol entries. The worlds write, the backend mirrors.

use anyhow::Result;
use lep_protocol::world::{Modules, Progress, ProtocolEntry, Trophies, PROTOCOLS};
use sqlx::{Row, SqlitePool};

/// Longest account name that is taken in.
const MAX_ACCOUNT: usize = 60;

fn is_account(name: &str) -> bool {
    !name.is_empty() && name.len() <= MAX_ACCOUNT
}

/// Replaces the list of modules of a world.
pub async fn store_modules(pool: &SqlitePool, world_id: &str, modules: &Modules) -> Result<()> {
    let mut tx = pool.begin().await?;
    sqlx::query("DELETE FROM modules WHERE world_id = ?")
        .bind(world_id)
        .execute(&mut *tx)
        .await?;
    for (position, module) in modules.modules.iter().enumerate() {
        sqlx::query(
            "INSERT OR REPLACE INTO modules (world_id, module_id, title, levels, position)
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(world_id)
        .bind(&module.id)
        .bind(&module.title)
        .bind(serde_json::to_string(&module.levels)?)
        .bind(position as i64)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

/// Stores where a student stands in a module. Returns false if the
/// payload makes no sense. A state older than the stored one is ignored.
pub async fn store_progress(
    pool: &SqlitePool,
    world_id: &str,
    time: i64,
    progress: &Progress,
) -> Result<bool> {
    if !is_account(&progress.account) || progress.module.is_empty() || progress.level < 1 {
        return Ok(false);
    }
    sqlx::query(
        "INSERT INTO progress
            (world_id, account, module_id, level, locked, percent, completed, tasks, reported_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (world_id, account, module_id) DO UPDATE SET
            level = excluded.level, locked = excluded.locked, percent = excluded.percent,
            completed = excluded.completed, tasks = excluded.tasks,
            reported_at = excluded.reported_at
         WHERE excluded.reported_at >= progress.reported_at",
    )
    .bind(world_id)
    .bind(&progress.account)
    .bind(&progress.module)
    .bind(progress.level)
    .bind(progress.locked)
    .bind(progress.percent.min(100))
    .bind(progress.completed)
    .bind(serde_json::to_string(&progress.tasks)?)
    .bind(time)
    .execute(pool)
    .await?;
    Ok(true)
}

/// Replaces the trophies of a student. Returns false if the payload makes
/// no sense. A list older than the stored one is ignored.
pub async fn store_trophies(
    pool: &SqlitePool,
    world_id: &str,
    time: i64,
    trophies: &Trophies,
) -> Result<bool> {
    if !is_account(&trophies.account) {
        return Ok(false);
    }
    let mut tx = pool.begin().await?;
    let newest: Option<i64> = sqlx::query_scalar(
        "SELECT reported_at FROM trophy_reports WHERE world_id = ? AND account = ?",
    )
    .bind(world_id)
    .bind(&trophies.account)
    .fetch_optional(&mut *tx)
    .await?;
    if newest.is_some_and(|newest| newest > time) {
        return Ok(true);
    }
    sqlx::query("DELETE FROM trophies WHERE world_id = ? AND account = ?")
        .bind(world_id)
        .bind(&trophies.account)
        .execute(&mut *tx)
        .await?;
    for trophy in &trophies.trophies {
        sqlx::query(
            "INSERT OR REPLACE INTO trophies (world_id, account, trophy_id, title, material)
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(world_id)
        .bind(&trophies.account)
        .bind(&trophy.id)
        .bind(&trophy.title)
        .bind(&trophy.material)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query(
        "INSERT OR REPLACE INTO trophy_reports (world_id, account, reported_at) VALUES (?, ?, ?)",
    )
    .bind(world_id)
    .bind(&trophies.account)
    .bind(time)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(true)
}

/// Appends an entry of a protocol. Returns false if the protocol is not
/// known or the entry names no account.
pub async fn store_protocol_entry(
    pool: &SqlitePool,
    world_id: &str,
    time: i64,
    entry: &ProtocolEntry,
) -> Result<bool> {
    if !PROTOCOLS.contains(&entry.protocol.as_str()) || !is_account(&entry.account) {
        return Ok(false);
    }
    sqlx::query(
        "INSERT INTO protocol_entries (world_id, protocol, time, account, fields)
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(world_id)
    .bind(&entry.protocol)
    .bind(time)
    .bind(&entry.account)
    .bind(serde_json::to_string(&entry.fields)?)
    .execute(pool)
    .await?;
    Ok(true)
}

/// What the backend knows about a world, as text for the terminal.
pub async fn describe(pool: &SqlitePool, world_id: &str) -> Result<String> {
    let mut lines = Vec::new();

    let modules = sqlx::query(
        "SELECT module_id, title, json_array_length(levels) AS levels
         FROM modules WHERE world_id = ? ORDER BY position",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    lines.push(format!("Modules: {}", modules.len()));
    for row in &modules {
        lines.push(format!(
            "  {}  \"{}\"  {} levels",
            row.get::<String, _>("module_id"),
            row.get::<String, _>("title"),
            row.get::<i64, _>("levels")
        ));
    }

    let progress = sqlx::query(
        "SELECT account, module_id, level, locked, percent, completed
         FROM progress WHERE world_id = ? ORDER BY account, module_id",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    lines.push(format!("Progress: {} entries", progress.len()));
    for row in &progress {
        let mut notes = Vec::new();
        if row.get::<bool, _>("locked") {
            notes.push("locked");
        }
        if row.get::<bool, _>("completed") {
            notes.push("module completed");
        }
        lines.push(format!(
            "  {}  {}  level {}  {} %{}",
            row.get::<String, _>("account"),
            row.get::<String, _>("module_id"),
            row.get::<i64, _>("level"),
            row.get::<i64, _>("percent"),
            if notes.is_empty() {
                String::new()
            } else {
                format!("  ({})", notes.join(", "))
            }
        ));
    }

    let trophies = sqlx::query(
        "SELECT account, count(*) AS count FROM trophies
         WHERE world_id = ? GROUP BY account ORDER BY account",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    lines.push(format!("Trophies: {} students", trophies.len()));
    for row in &trophies {
        lines.push(format!(
            "  {}  {}",
            row.get::<String, _>("account"),
            row.get::<i64, _>("count")
        ));
    }

    let protocols = sqlx::query(
        "SELECT protocol, count(*) AS count FROM protocol_entries
         WHERE world_id = ? GROUP BY protocol ORDER BY protocol",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    lines.push("Protocols:".to_owned());
    if protocols.is_empty() {
        lines.push("  no entries".to_owned());
    }
    for row in &protocols {
        lines.push(format!(
            "  {}  {} entries",
            row.get::<String, _>("protocol"),
            row.get::<i64, _>("count")
        ));
    }

    let newest = sqlx::query(
        "SELECT protocol, time, account, fields FROM protocol_entries
         WHERE world_id = ? ORDER BY id DESC LIMIT 5",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    if !newest.is_empty() {
        lines.push("Newest protocol entries:".to_owned());
        for row in newest.iter().rev() {
            lines.push(format!(
                "  {}  {}  {}  {}",
                row.get::<i64, _>("time"),
                row.get::<String, _>("protocol"),
                row.get::<String, _>("account"),
                row.get::<String, _>("fields")
            ));
        }
    }
    Ok(lines.join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, worlds};
    use lep_protocol::world::{Level, Module, TaskProgress, TaskType, Trophy};
    use std::collections::BTreeMap;

    async fn setup() -> (SqlitePool, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        (pool, world.id)
    }

    fn progress(level: u32, percent: u32) -> Progress {
        Progress {
            account: "anna".to_owned(),
            module: "lep_math:math".to_owned(),
            level,
            locked: false,
            percent,
            completed: false,
            tasks: vec![TaskProgress {
                id: "add_10".to_owned(),
                solved: 3,
                required: 10,
            }],
        }
    }

    async fn level_of(pool: &SqlitePool) -> (i64, i64) {
        let row = sqlx::query("SELECT level, percent FROM progress")
            .fetch_one(pool)
            .await
            .unwrap();
        (row.get("level"), row.get("percent"))
    }

    #[tokio::test]
    async fn keeps_the_newest_state_of_a_student() {
        let (pool, world) = setup().await;
        assert!(store_progress(&pool, &world, 100, &progress(1, 30))
            .await
            .unwrap());
        assert!(store_progress(&pool, &world, 200, &progress(2, 0))
            .await
            .unwrap());
        assert_eq!(level_of(&pool).await, (2, 0));

        // An older state that arrives late changes nothing.
        assert!(store_progress(&pool, &world, 150, &progress(1, 90))
            .await
            .unwrap());
        assert_eq!(level_of(&pool).await, (2, 0));

        let count: i64 = sqlx::query_scalar("SELECT count(*) FROM progress")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(count, 1);
    }

    #[tokio::test]
    async fn refuses_progress_that_makes_no_sense() {
        let (pool, world) = setup().await;
        let mut nobody = progress(1, 0);
        nobody.account = String::new();
        assert!(!store_progress(&pool, &world, 100, &nobody).await.unwrap());
        assert!(!store_progress(&pool, &world, 100, &progress(0, 0))
            .await
            .unwrap());

        // More than everything is everything.
        assert!(store_progress(&pool, &world, 100, &progress(1, 250))
            .await
            .unwrap());
        assert_eq!(level_of(&pool).await, (1, 100));
    }

    #[tokio::test]
    async fn replaces_modules_and_trophies_as_a_whole() {
        let (pool, world) = setup().await;
        let module = |id: &str| Module {
            id: id.to_owned(),
            title: "Title".to_owned(),
            levels: vec![Level {
                stage: true,
                tasks: vec![TaskType {
                    id: "t".to_owned(),
                    title: "T".to_owned(),
                    required: 5,
                }],
            }],
        };
        store_modules(
            &pool,
            &world,
            &Modules {
                modules: vec![module("a"), module("b")],
            },
        )
        .await
        .unwrap();
        store_modules(
            &pool,
            &world,
            &Modules {
                modules: vec![module("b")],
            },
        )
        .await
        .unwrap();
        let ids: Vec<String> = sqlx::query_scalar("SELECT module_id FROM modules")
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(ids, ["b"]);

        let trophy = |id: &str| Trophy {
            id: id.to_owned(),
            title: "Cup".to_owned(),
            material: "gold".to_owned(),
        };
        let list = |trophies| Trophies {
            account: "anna".to_owned(),
            trophies,
        };
        assert!(store_trophies(&pool, &world, 100, &list(vec![trophy("a")]))
            .await
            .unwrap());
        assert!(
            store_trophies(&pool, &world, 200, &list(vec![trophy("a"), trophy("b")]))
                .await
                .unwrap()
        );
        // An older list that arrives late changes nothing.
        assert!(store_trophies(&pool, &world, 150, &list(vec![]))
            .await
            .unwrap());
        let count: i64 = sqlx::query_scalar("SELECT count(*) FROM trophies")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(count, 2);
        assert!(!store_trophies(
            &pool,
            &world,
            300,
            &Trophies {
                account: String::new(),
                trophies: vec![]
            }
        )
        .await
        .unwrap());
    }

    #[tokio::test]
    async fn appends_entries_of_known_protocols() {
        let (pool, world) = setup().await;
        let entry = |protocol: &str, account: &str| ProtocolEntry {
            protocol: protocol.to_owned(),
            account: account.to_owned(),
            fields: BTreeMap::from([("text".to_owned(), "hello".to_owned())]),
        };
        assert!(
            store_protocol_entry(&pool, &world, 100, &entry("chat", "anna"))
                .await
                .unwrap()
        );
        assert!(
            store_protocol_entry(&pool, &world, 101, &entry("chat", "anna"))
                .await
                .unwrap()
        );
        assert!(
            !store_protocol_entry(&pool, &world, 102, &entry("diary", "anna"))
                .await
                .unwrap()
        );
        assert!(
            !store_protocol_entry(&pool, &world, 103, &entry("chat", ""))
                .await
                .unwrap()
        );

        let row =
            sqlx::query("SELECT count(*) AS count, min(fields) AS fields FROM protocol_entries")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(row.get::<i64, _>("count"), 2);
        assert_eq!(row.get::<String, _>("fields"), r#"{"text":"hello"}"#);
    }

    #[tokio::test]
    async fn describes_what_it_knows() {
        let (pool, world) = setup().await;
        let empty = describe(&pool, &world).await.unwrap();
        assert!(empty.contains("Modules: 0") && empty.contains("no entries"));

        store_progress(&pool, &world, 100, &progress(3, 40))
            .await
            .unwrap();
        let entry = ProtocolEntry {
            protocol: "desk".to_owned(),
            account: "teacher".to_owned(),
            fields: BTreeMap::new(),
        };
        store_protocol_entry(&pool, &world, 100, &entry)
            .await
            .unwrap();
        let text = describe(&pool, &world).await.unwrap();
        assert!(text.contains("anna  lep_math:math  level 3  40 %"));
        assert!(text.contains("desk  1 entries"));
    }
}
