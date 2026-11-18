//! Display names: the name a player chose to be shown under in a world.
//!
//! Nobody approves a name. The world reports it, the backend mirrors it
//! and tells the teachers of the group by mail, and a teacher can order
//! the world to take a name away or to lock choosing one.

use anyhow::Result;
use lep_protocol::web::{DisplayNameAction, DisplayNameEntry};
use lep_protocol::world::{
    DisplayName, RemoveDisplayName, SetDisplayLocked, JOB_REMOVE_DISPLAY_NAME,
    JOB_SET_DISPLAY_LOCKED,
};
use sqlx::{Row, SqlitePool};

use crate::app::AppState;
use crate::teachers::is_account;
use crate::{jobs, mail};

/// Longest display name that is taken in, in bytes. The worlds allow 16
/// characters.
const MAX_NAME: usize = 64;

/// What a reported state changed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stored {
    /// The payload makes no sense.
    Invalid,
    /// Stored, or older than what is known and dropped.
    Kept,
    /// Stored, and the account has a name it did not have before.
    NewName,
}

/// Stores the display name of an account as its world reported it.
pub async fn store(
    pool: &SqlitePool,
    world_id: &str,
    time: i64,
    reported: &DisplayName,
) -> Result<Stored> {
    let name = reported.name.as_deref().filter(|name| !name.is_empty());
    if !is_account(&reported.account)
        || name.is_some_and(|name| name.len() > MAX_NAME || name.chars().any(char::is_control))
    {
        return Ok(Stored::Invalid);
    }
    let mut tx = pool.begin().await?;
    let known = sqlx::query(
        "SELECT name, reported_at FROM display_names WHERE world_id = ? AND account = ?",
    )
    .bind(world_id)
    .bind(&reported.account)
    .fetch_optional(&mut *tx)
    .await?;
    let before: Option<String> = match &known {
        Some(row) if row.get::<i64, _>("reported_at") > time => return Ok(Stored::Kept),
        Some(row) => row.get("name"),
        None => None,
    };
    sqlx::query(
        "INSERT OR REPLACE INTO display_names
             (world_id, account, name, changed_at, locked, reported_at)
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(world_id)
    .bind(&reported.account)
    .bind(name)
    .bind(reported.changed_at)
    .bind(reported.locked)
    .bind(time)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(match name {
        Some(name) if before.as_deref() != Some(name) => Stored::NewName,
        _ => Stored::Kept,
    })
}

/// Tells the teachers of a group by mail that one of its students has a
/// new display name. Only teachers with a confirmed address get one.
/// The name of a teacher is nobody's business: teachers are trusted.
pub async fn tell_teachers(
    app: &AppState,
    world_id: &str,
    account: &str,
    name: &str,
) -> Result<()> {
    let group: Option<String> = sqlx::query_scalar("SELECT name FROM worlds WHERE id = ?")
        .bind(world_id)
        .fetch_optional(&app.db)
        .await?;
    let Some(group) = group else {
        return Ok(());
    };
    if student(&app.db, world_id, account).await?.is_none() {
        return Ok(());
    }
    let teachers = sqlx::query(
        "SELECT teachers.account, teachers.email
         FROM group_teachers JOIN teachers ON teachers.account = group_teachers.account
         WHERE group_teachers.world_id = ? AND teachers.email IS NOT NULL
         ORDER BY teachers.account",
    )
    .bind(world_id)
    .fetch_all(&app.db)
    .await?;
    for teacher in &teachers {
        let to: String = teacher.get("email");
        let teacher_account: String = teacher.get("account");
        let mail = mail::display_name(
            &app.public_url,
            &to,
            &teacher_account,
            &group,
            world_id,
            account,
            name,
        );
        app.mailer.send_later(mail, &teacher_account).await;
    }
    tracing::info!(group = %world_id, %account, mails = teachers.len(), "new display name");
    Ok(())
}

/// Returns the stored name of an account of a group that exists in its
/// world, as it is written there.
async fn student(pool: &SqlitePool, world_id: &str, account: &str) -> Result<Option<String>> {
    Ok(sqlx::query_scalar(
        "SELECT account FROM students WHERE account = ? AND world_id = ? AND state = 'active'",
    )
    .bind(account)
    .bind(world_id)
    .fetch_optional(pool)
    .await?)
}

/// Orders the world of a group to take the display name of a student
/// away. Returns false if the group has no such account that exists.
/// @param by Account name of the teacher, for the protocol of the world.
pub async fn remove(pool: &SqlitePool, world_id: &str, account: &str, by: &str) -> Result<bool> {
    let Some(account) = student(pool, world_id, account).await? else {
        return Ok(false);
    };
    let payload = RemoveDisplayName {
        account: account.clone(),
        by: by.to_owned(),
    };
    jobs::add_about(
        pool,
        world_id,
        JOB_REMOVE_DISPLAY_NAME,
        &serde_json::to_value(payload)?,
        Some(&account),
    )
    .await?;
    Ok(true)
}

/// Orders the world of a group to lock or unlock choosing a display name
/// for a student. Returns false if the group has no such account that
/// exists.
/// @param by Account name of the teacher, for the protocol of the world.
pub async fn set_locked(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
    locked: bool,
    by: &str,
) -> Result<bool> {
    let Some(account) = student(pool, world_id, account).await? else {
        return Ok(false);
    };
    let payload = SetDisplayLocked {
        account: account.clone(),
        locked,
        by: by.to_owned(),
    };
    jobs::add_about(
        pool,
        world_id,
        JOB_SET_DISPLAY_LOCKED,
        &serde_json::to_value(payload)?,
        Some(&account),
    )
    .await?;
    Ok(true)
}

fn action_of(text: &str) -> Option<DisplayNameAction> {
    Some(match text {
        "chosen" => DisplayNameAction::Chosen,
        "given_up" => DisplayNameAction::GivenUp,
        "removed" => DisplayNameAction::Removed,
        "locked" => DisplayNameAction::Locked,
        "unlocked" => DisplayNameAction::Unlocked,
        _ => return None,
    })
}

/// Returns what happened to the display name of a student, newest
/// first, or `None` if the group has no such account that exists. It is
/// read from the protocol of the names and goes when that is deleted.
pub async fn history(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
) -> Result<Option<Vec<DisplayNameEntry>>> {
    let Some(account) = student(pool, world_id, account).await? else {
        return Ok(None);
    };
    let rows = sqlx::query(
        "SELECT time, fields FROM protocol_entries
         WHERE world_id = ? AND protocol = 'names' AND account = ?
         ORDER BY time DESC, rowid DESC",
    )
    .bind(world_id)
    .bind(&account)
    .fetch_all(pool)
    .await?;
    let mut entries = Vec::new();
    for row in &rows {
        let fields: serde_json::Value = serde_json::from_str(row.get("fields")).unwrap_or_default();
        let text = |key: &str| fields.get(key).and_then(|value| value.as_str());
        let Some(action) = text("action").and_then(action_of) else {
            continue;
        };
        entries.push(DisplayNameEntry {
            time: row.get("time"),
            action,
            name: text("name").map(str::to_owned),
            by: text("by").unwrap_or(&account).to_owned(),
        });
    }
    Ok(Some(entries))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mail::Mailer;
    use crate::{db, state, worlds};
    use lep_protocol::world::ProtocolEntry;
    use std::collections::BTreeMap;

    async fn setup() -> (AppState, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        sqlx::query(
            "INSERT INTO students (account, world_id, state, created_at)
             VALUES ('klugeEule', ?1, 'active', 0), ('stillerBach', ?1, 'draft', 0)",
        )
        .bind(&world.id)
        .execute(&pool)
        .await
        .unwrap();
        let app = AppState::with(pool, Mailer::memory(), "https://lep.schule.example");
        (app, world.id)
    }

    fn reported(name: Option<&str>, changed_at: Option<i64>, locked: bool) -> DisplayName {
        DisplayName {
            account: "klugeEule".to_owned(),
            name: name.map(str::to_owned),
            changed_at,
            locked,
        }
    }

    async fn known(pool: &SqlitePool, world: &str) -> (Option<String>, Option<i64>, bool) {
        sqlx::query_as(
            "SELECT name, changed_at, locked FROM display_names
             WHERE world_id = ? AND account = 'klugeEule'",
        )
        .bind(world)
        .fetch_one(pool)
        .await
        .unwrap()
    }

    #[tokio::test]
    async fn mirrors_the_state_and_says_when_a_name_is_new() {
        let (app, world) = setup().await;
        let pool = &app.db;
        let lena = reported(Some("Lena"), Some(90), false);
        assert_eq!(
            store(pool, &world, 100, &lena).await.unwrap(),
            Stored::NewName
        );
        assert_eq!(
            known(pool, &world).await,
            (Some("Lena".to_owned()), Some(90), false)
        );
        // The same state again, as after the backend asked for everything.
        assert_eq!(store(pool, &world, 110, &lena).await.unwrap(), Stored::Kept);
        // Locked: the name is not new.
        let locked = reported(Some("Lena"), Some(90), true);
        assert_eq!(
            store(pool, &world, 120, &locked).await.unwrap(),
            Stored::Kept
        );
        assert!(known(pool, &world).await.2);
        // Taken away, then chosen again: new again.
        let none = reported(None, None, true);
        assert_eq!(store(pool, &world, 130, &none).await.unwrap(), Stored::Kept);
        assert_eq!(known(pool, &world).await, (None, None, true));
        assert_eq!(
            store(pool, &world, 140, &lena).await.unwrap(),
            Stored::NewName
        );
        let lea = reported(Some("Lea"), Some(150), false);
        assert_eq!(
            store(pool, &world, 150, &lea).await.unwrap(),
            Stored::NewName
        );
    }

    #[tokio::test]
    async fn drops_an_older_state_and_what_makes_no_sense() {
        let (app, world) = setup().await;
        let pool = &app.db;
        let lea = reported(Some("Lea"), Some(200), false);
        store(pool, &world, 200, &lea).await.unwrap();
        let lena = reported(Some("Lena"), Some(90), false);
        assert_eq!(store(pool, &world, 100, &lena).await.unwrap(), Stored::Kept);
        assert_eq!(known(pool, &world).await.0.as_deref(), Some("Lea"));

        let mut bad = reported(Some("Lena"), None, false);
        bad.account = "kluge Eule".to_owned();
        assert_eq!(
            store(pool, &world, 300, &bad).await.unwrap(),
            Stored::Invalid
        );
        let long = "x".repeat(65);
        for name in ["Le\nna", long.as_str()] {
            let bad = reported(Some(name), None, false);
            assert_eq!(
                store(pool, &world, 300, &bad).await.unwrap(),
                Stored::Invalid
            );
        }
        // An empty name is no name.
        let empty = reported(Some(""), None, false);
        assert_eq!(
            store(pool, &world, 300, &empty).await.unwrap(),
            Stored::Kept
        );
        assert_eq!(known(pool, &world).await.0, None);
    }

    #[tokio::test]
    async fn tells_the_teachers_of_the_group_with_a_confirmed_address() {
        let (app, world) = setup().await;
        let (other, _) = worlds::add(&app.db, "8a").await.unwrap();
        for (account, email) in [
            ("lehrer1", Some("lehrer1@schule.example")),
            ("lehrer2", None),
            ("lehrer3", Some("lehrer3@schule.example")),
        ] {
            sqlx::query("INSERT INTO teachers (account, email, created_at) VALUES (?, ?, 0)")
                .bind(account)
                .bind(email)
                .execute(&app.db)
                .await
                .unwrap();
        }
        for (group, account) in [
            (&world, "lehrer1"),
            (&world, "lehrer2"),
            (&other.id, "lehrer3"),
        ] {
            sqlx::query("INSERT INTO group_teachers (world_id, account) VALUES (?, ?)")
                .bind(group)
                .bind(account)
                .execute(&app.db)
                .await
                .unwrap();
        }

        // Not for an account that is no student of the group.
        tell_teachers(&app, &world, "lehrer2", "Herr Maier")
            .await
            .unwrap();
        tell_teachers(&app, &other.id, "klugeEule", "Lena")
            .await
            .unwrap();
        assert!(app.mailer.kept().is_empty());

        tell_teachers(&app, &world, "klugeEule", "Lena")
            .await
            .unwrap();
        let mails = app.mailer.kept();
        assert_eq!(mails.len(), 1);
        assert_eq!(mails[0].to, "lehrer1@schule.example");
        assert!(mails[0].subject.contains("7b"));
        assert!(mails[0].body.contains("klugeEule"));
        assert!(mails[0].body.contains("Lena"));
        let link = format!("https://lep.schule.example/groups/{world}/students");
        assert!(mails[0].body.contains(&link));
    }

    #[tokio::test]
    async fn orders_removing_and_locking_for_students_that_exist() {
        let (app, world) = setup().await;
        let pool = &app.db;
        assert!(remove(pool, &world, "KLUGEEULE", "lehrer1").await.unwrap());
        assert!(set_locked(pool, &world, "klugeEule", true, "lehrer1")
            .await
            .unwrap());
        for account in ["stillerBach", "niemand"] {
            assert!(!remove(pool, &world, account, "lehrer1").await.unwrap());
            assert!(!set_locked(pool, &world, account, true, "lehrer1")
                .await
                .unwrap());
        }
        let sent = jobs::take_waiting(pool, &world).await.unwrap();
        assert_eq!(sent.len(), 2);
        assert_eq!(sent[0].kind, JOB_REMOVE_DISPLAY_NAME);
        assert_eq!(
            sent[0].payload,
            serde_json::json!({ "account": "klugeEule", "by": "lehrer1" })
        );
        assert_eq!(sent[1].kind, JOB_SET_DISPLAY_LOCKED);
        assert_eq!(
            sent[1].payload,
            serde_json::json!({ "account": "klugeEule", "locked": true, "by": "lehrer1" })
        );
    }

    #[tokio::test]
    async fn reads_the_history_from_the_protocol_newest_first() {
        let (app, world) = setup().await;
        let pool = &app.db;
        let entry = |account: &str, fields: &[(&str, &str)]| ProtocolEntry {
            protocol: "names".to_owned(),
            account: account.to_owned(),
            fields: fields
                .iter()
                .map(|(key, value)| ((*key).to_owned(), (*value).to_owned()))
                .collect::<BTreeMap<_, _>>(),
        };
        let chosen = [
            ("action", "chosen"),
            ("name", "Lena Maier"),
            ("by", "klugeEule"),
        ];
        let removed = [
            ("action", "removed"),
            ("name", "Lena Maier"),
            ("by", "lehrer1"),
        ];
        let locked = [("action", "locked"), ("by", "lehrer1")];
        let odd = [("action", "painted"), ("by", "lehrer1")];
        for (time, account, fields) in [
            (100, "klugeEule", &chosen[..]),
            (200, "klugeEule", &removed[..]),
            (300, "klugeEule", &locked[..]),
            (400, "klugeEule", &odd[..]),
            (500, "frohesReh", &chosen[..]),
        ] {
            assert!(
                state::store_protocol_entry(pool, &world, time, &entry(account, fields))
                    .await
                    .unwrap()
            );
        }
        let entries = history(pool, &world, "klugeEule").await.unwrap().unwrap();
        let seen: Vec<_> = entries
            .iter()
            .map(|entry| {
                (
                    entry.time,
                    entry.action,
                    entry.name.as_deref(),
                    entry.by.as_str(),
                )
            })
            .collect();
        assert_eq!(
            seen,
            [
                (300, DisplayNameAction::Locked, None, "lehrer1"),
                (
                    200,
                    DisplayNameAction::Removed,
                    Some("Lena Maier"),
                    "lehrer1"
                ),
                (
                    100,
                    DisplayNameAction::Chosen,
                    Some("Lena Maier"),
                    "klugeEule"
                ),
            ]
        );
        assert_eq!(history(pool, &world, "niemand").await.unwrap(), None);
    }
}
