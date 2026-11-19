//! Deleting an account on request.
//!
//! The world leads: the backend orders, the world deletes and reports
//! it, and only then the copies here go. What stays for good is a note
//! without content: who, when, which account, in which group.

use anyhow::Result;
use lep_protocol::web::{Removal, RemovalRefusal};
use lep_protocol::world::{AccountRemoved, AccountUsed, RemoveAccount, JOB_REMOVE_ACCOUNT};
use sqlx::{Row, SqlitePool};

use crate::jobs;

/// Why deleting an account was not ordered.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderError {
    /// The group has no such account that exists in its world.
    NotFound,
    /// Somebody has logged in with the account: only the school
    /// administration deletes it.
    Used,
}

/// Orders the world of a group to delete the account of a student.
/// Ordering it again while the world has not answered changes nothing.
/// @param by Account name of who orders it.
/// @param school_admin True if they belong to the school administration.
///   Everybody else only takes back accounts nobody ever used, and the
///   world checks that again.
pub async fn order(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
    by: &str,
    school_admin: bool,
) -> Result<Result<(), OrderError>> {
    // The name as it is stored: the engine tells letter cases apart.
    let row = sqlx::query(
        "SELECT account, used FROM students
         WHERE account = ? AND world_id = ? AND state = 'active'",
    )
    .bind(account)
    .bind(world_id)
    .fetch_optional(pool)
    .await?;
    let Some(row) = row else {
        return Ok(Err(OrderError::NotFound));
    };
    let account: String = row.get("account");
    if !school_admin && row.get::<bool, _>("used") {
        return Ok(Err(OrderError::Used));
    }
    if is_waiting(pool, world_id, &account).await? {
        return Ok(Ok(()));
    }
    let payload = RemoveAccount {
        account: account.clone(),
        only_unused: !school_admin,
        by: by.to_owned(),
    };
    jobs::add_about(
        pool,
        world_id,
        JOB_REMOVE_ACCOUNT,
        &serde_json::to_value(payload)?,
        Some(&account),
    )
    .await?;
    Ok(Ok(()))
}

async fn is_waiting(pool: &SqlitePool, world_id: &str, account: &str) -> Result<bool> {
    let waiting: Option<i64> = sqlx::query_scalar(
        "SELECT 1 FROM jobs
         WHERE world_id = ? AND kind = ? AND subject = ? AND finished_at IS NULL LIMIT 1",
    )
    .bind(world_id)
    .bind(JOB_REMOVE_ACCOUNT)
    .bind(account)
    .fetch_optional(pool)
    .await?;
    Ok(waiting.is_some())
}

/// Takes back the order to delete an account, as long as the world has
/// not answered. A world that is doing it at this very moment still
/// deletes: its report counts. Returns false if no order was waiting.
pub async fn take_back(pool: &SqlitePool, world_id: &str, account: &str) -> Result<bool> {
    let removed = sqlx::query(
        "DELETE FROM jobs
         WHERE world_id = ? AND kind = ? AND subject = ? COLLATE NOCASE
           AND finished_at IS NULL",
    )
    .bind(world_id)
    .bind(JOB_REMOVE_ACCOUNT)
    .bind(account)
    .execute(pool)
    .await?
    .rows_affected();
    Ok(removed > 0)
}

/// Reads the word a world answered with when it did not delete.
pub fn refusal_of(message: &str) -> RemovalRefusal {
    match message {
        "used" => RemovalRefusal::Used,
        "staff" => RemovalRefusal::Staff,
        "unknown" => RemovalRefusal::Unknown,
        "incomplete" | "online" | "busy" => RemovalRefusal::Incomplete,
        _ => RemovalRefusal::Failed,
    }
}

fn is_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 60
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// Notes that somebody has logged in with an account. Returns false if
/// the payload makes no sense.
pub async fn note_used(pool: &SqlitePool, world_id: &str, used: &AccountUsed) -> Result<bool> {
    if !is_name(&used.account) {
        return Ok(false);
    }
    // Teachers log in as well; only students are kept here.
    sqlx::query("UPDATE students SET used = 1 WHERE account = ? AND world_id = ? AND used = 0")
        .bind(&used.account)
        .bind(world_id)
        .execute(pool)
        .await?;
    Ok(true)
}

/// Deletes everything the backend keeps about an account its world has
/// deleted, and writes the note that stays. Only data of this world is
/// touched. Returns false if the payload makes no sense.
/// @param time When the world deleted, by its clock.
pub async fn note_removed(
    pool: &SqlitePool,
    world_id: &str,
    time: i64,
    removed: &AccountRemoved,
) -> Result<bool> {
    let by = removed.by.as_deref().filter(|by| !by.is_empty());
    if !is_name(&removed.account) || by.is_some_and(|by| !is_name(by)) {
        return Ok(false);
    }
    let account = removed.account.as_str();
    let mut tx = pool.begin().await?;

    for delete in [
        "DELETE FROM progress WHERE world_id = ? AND account = ?",
        "DELETE FROM trophies WHERE world_id = ? AND account = ?",
        "DELETE FROM trophy_reports WHERE world_id = ? AND account = ?",
        "DELETE FROM display_names WHERE world_id = ? AND account = ?",
    ] {
        sqlx::query(delete)
            .bind(world_id)
            .bind(account)
            .execute(&mut *tx)
            .await?;
    }
    // The same rule as in the world: what the account caused itself, and
    // private messages to it. Lines of others that only mention it stay
    // until the year is closed.
    sqlx::query(
        "DELETE FROM protocol_entries
         WHERE world_id = ?1
           AND (account = ?2 OR json_extract(fields, '$.recipient') = ?2)",
    )
    .bind(world_id)
    .bind(account)
    .execute(&mut *tx)
    .await?;
    // Orders about the account. The one that deleted it stays until the
    // world has answered for it.
    sqlx::query("DELETE FROM jobs WHERE world_id = ? AND subject = ? AND kind != ?")
        .bind(world_id)
        .bind(account)
        .bind(JOB_REMOVE_ACCOUNT)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM students WHERE account = ? AND world_id = ?")
        .bind(account)
        .bind(world_id)
        .execute(&mut *tx)
        .await?;

    let group: Option<String> = sqlx::query_scalar("SELECT name FROM worlds WHERE id = ?")
        .bind(world_id)
        .fetch_optional(&mut *tx)
        .await?;
    sqlx::query(
        "INSERT INTO account_removals (time, account, world_id, group_name, ordered_by)
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(time)
    .bind(account)
    .bind(world_id)
    .bind(group.unwrap_or_default())
    .bind(by)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(true)
}

/// Lists the notes of all deleted accounts, newest first.
pub async fn list(pool: &SqlitePool) -> Result<Vec<Removal>> {
    let rows = sqlx::query(
        "SELECT time, account, group_name, ordered_by FROM account_removals
         ORDER BY time DESC, id DESC",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .iter()
        .map(|row| Removal {
            time: row.get("time"),
            account: row.get("account"),
            group: row.get("group_name"),
            by: row.get("ordered_by"),
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, students, worlds};
    use lep_protocol::web::ChangeState;
    use lep_protocol::world::JobResult;
    use serde_json::json;

    async fn setup() -> (SqlitePool, String, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (first, _) = worlds::add(&pool, "7b").await.unwrap();
        let (second, _) = worlds::add(&pool, "8a").await.unwrap();
        sqlx::query(
            "INSERT INTO students (account, world_id, state, created_at) VALUES
             ('klugeEule', ?1, 'active', 0), ('stillerBach', ?1, 'active', 0),
             ('neuerDachs', ?1, 'draft', 0), ('froherWal', ?2, 'active', 0)",
        )
        .bind(&first.id)
        .bind(&second.id)
        .execute(&pool)
        .await
        .unwrap();
        (pool, first.id, second.id)
    }

    fn used(account: &str) -> AccountUsed {
        AccountUsed {
            account: account.to_owned(),
        }
    }

    fn removed(account: &str, by: Option<&str>) -> AccountRemoved {
        AccountRemoved {
            account: account.to_owned(),
            by: by.map(str::to_owned),
        }
    }

    async fn student(pool: &SqlitePool, world: &str, account: &str) -> lep_protocol::web::Student {
        students::list(pool, world)
            .await
            .unwrap()
            .into_iter()
            .find(|student| student.account == account)
            .unwrap()
    }

    async fn count(pool: &SqlitePool, sql: &'static str) -> i64 {
        sqlx::query_scalar(sql).fetch_one(pool).await.unwrap()
    }

    #[tokio::test]
    async fn notes_which_accounts_were_used() {
        let (pool, first, second) = setup().await;
        assert!(!student(&pool, &first, "klugeEule").await.used);
        assert!(note_used(&pool, &first, &used("klugeEule")).await.unwrap());
        assert!(note_used(&pool, &first, &used("klugeEule")).await.unwrap());
        // A teacher, and a student of another group: nothing changes.
        assert!(note_used(&pool, &first, &used("lehrer1")).await.unwrap());
        assert!(note_used(&pool, &first, &used("froherWal")).await.unwrap());
        assert!(!note_used(&pool, &first, &used("kluge Eule")).await.unwrap());

        assert!(student(&pool, &first, "klugeEule").await.used);
        assert!(!student(&pool, &first, "stillerBach").await.used);
        assert!(!student(&pool, &second, "froherWal").await.used);
    }

    #[tokio::test]
    async fn a_teacher_only_takes_back_what_nobody_used() {
        let (pool, first, _) = setup().await;
        note_used(&pool, &first, &used("klugeEule")).await.unwrap();

        let refused = order(&pool, &first, "klugeEule", "lehrer1", false).await;
        assert_eq!(refused.unwrap(), Err(OrderError::Used));
        assert!(jobs::take_waiting(&pool, &first).await.unwrap().is_empty());

        let unused = order(&pool, &first, "stillerbach", "lehrer1", false).await;
        assert_eq!(unused.unwrap(), Ok(()));
        let waiting = jobs::take_waiting(&pool, &first).await.unwrap();
        assert_eq!(waiting.len(), 1);
        assert_eq!(waiting[0].kind, JOB_REMOVE_ACCOUNT);
        // The world checks again, and gets the name as it is written.
        assert_eq!(
            waiting[0].payload,
            json!({ "account": "stillerBach", "only_unused": true, "by": "lehrer1" })
        );
        let shown = student(&pool, &first, "stillerBach").await;
        assert_eq!(shown.removal, Some(ChangeState::Pending));
        assert_eq!(shown.removal_refusal, None);
    }

    #[tokio::test]
    async fn the_school_administration_deletes_used_accounts() {
        let (pool, first, _) = setup().await;
        note_used(&pool, &first, &used("klugeEule")).await.unwrap();
        let ordered = order(&pool, &first, "klugeEule", "leitung", true).await;
        assert_eq!(ordered.unwrap(), Ok(()));
        // Ordering again while it waits adds nothing.
        let again = order(&pool, &first, "klugeEule", "leitung", true).await;
        assert_eq!(again.unwrap(), Ok(()));
        let waiting = jobs::take_waiting(&pool, &first).await.unwrap();
        assert_eq!(waiting.len(), 1);
        assert_eq!(
            waiting[0].payload,
            json!({ "account": "klugeEule", "only_unused": false, "by": "leitung" })
        );
    }

    #[tokio::test]
    async fn orders_only_for_accounts_that_exist_in_the_group() {
        let (pool, first, _) = setup().await;
        for account in ["neuerDachs", "froherWal", "niemand"] {
            let result = order(&pool, &first, account, "leitung", true).await;
            assert_eq!(result.unwrap(), Err(OrderError::NotFound), "{account}");
        }
    }

    #[tokio::test]
    async fn shows_why_the_world_refused_and_lets_an_order_be_taken_back() {
        let (pool, first, _) = setup().await;
        order(&pool, &first, "klugeEule", "lehrer1", false)
            .await
            .unwrap()
            .unwrap();
        let job = jobs::take_waiting(&pool, &first).await.unwrap().remove(0);
        let answer = JobResult {
            ok: false,
            message: "used".to_owned(),
        };
        jobs::finish(&pool, &first, &job.id, &answer).await.unwrap();
        let shown = student(&pool, &first, "klugeEule").await;
        assert_eq!(shown.removal, Some(ChangeState::Refused));
        assert_eq!(shown.removal_refusal, Some(RemovalRefusal::Used));
        // An answer is no order that waits.
        assert!(!take_back(&pool, &first, "klugeEule").await.unwrap());

        order(&pool, &first, "klugeEule", "leitung", true)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            student(&pool, &first, "klugeEule").await.removal,
            Some(ChangeState::Pending)
        );
        assert!(take_back(&pool, &first, "klugeEule").await.unwrap());
        assert!(jobs::take_waiting(&pool, &first).await.unwrap().is_empty());
        // The older refusal shows again.
        assert_eq!(
            student(&pool, &first, "klugeEule").await.removal,
            Some(ChangeState::Refused)
        );
    }

    #[test]
    fn reads_the_words_of_the_world() {
        assert_eq!(refusal_of("used"), RemovalRefusal::Used);
        assert_eq!(refusal_of("staff"), RemovalRefusal::Staff);
        assert_eq!(refusal_of("unknown"), RemovalRefusal::Unknown);
        assert_eq!(refusal_of("incomplete"), RemovalRefusal::Incomplete);
        assert_eq!(refusal_of("online"), RemovalRefusal::Incomplete);
        assert_eq!(
            refusal_of("this world does not know the job 'remove_account'"),
            RemovalRefusal::Failed
        );
    }

    #[tokio::test]
    async fn deletes_the_copies_and_keeps_a_note() {
        let (pool, first, second) = setup().await;
        for world in [&first, &second] {
            for account in ["klugeEule", "stillerBach"] {
                sqlx::query(
                    "INSERT INTO progress (world_id, account, module_id, level, locked, percent,
                        completed, tasks, reported_at) VALUES (?, ?, 'm:m', 1, 0, 0, 0, '[]', 0)",
                )
                .bind(world)
                .bind(account)
                .execute(&pool)
                .await
                .unwrap();
            }
        }
        sqlx::query(
            "INSERT INTO trophies (world_id, account, trophy_id, title, material)
             VALUES (?1, 'klugeEule', 't', 'T', 'gold');
             INSERT INTO trophy_reports (world_id, account, reported_at)
             VALUES (?1, 'klugeEule', 0);
             INSERT INTO display_names (world_id, account, name, reported_at)
             VALUES (?1, 'klugeEule', 'Hans', 0);
             INSERT INTO protocol_entries (world_id, protocol, time, account, fields) VALUES
             (?1, 'chat', 1, 'klugeEule', '{\"kind\":\"chat\",\"text\":\"hallo\"}'),
             (?1, 'chat', 2, 'stillerBach', '{\"kind\":\"private\",\"recipient\":\"klugeEule\"}'),
             (?1, 'chat', 3, 'stillerBach', '{\"kind\":\"chat\",\"text\":\"klugeEule\"}'),
             (?1, 'desk', 4, 'lehrer1', '{\"action\":\"bring\",\"targets\":\"klugeEule\"}'),
             (?1, 'names', 5, 'klugeEule', '{\"action\":\"chosen\",\"name\":\"Hans\"}')",
        )
        .bind(&first)
        .execute(&pool)
        .await
        .unwrap();
        jobs::add_about(&pool, &first, "set_password", &json!({}), Some("klugeEule"))
            .await
            .unwrap();
        order(&pool, &first, "klugeEule", "leitung", true)
            .await
            .unwrap()
            .unwrap();

        // Nonsense changes nothing.
        assert!(
            !note_removed(&pool, &first, 50, &removed("kluge Eule", None))
                .await
                .unwrap()
        );
        assert!(
            note_removed(&pool, &first, 100, &removed("klugeEule", Some("leitung")))
                .await
                .unwrap()
        );

        let names: Vec<String> = students::list(&pool, &first)
            .await
            .unwrap()
            .into_iter()
            .map(|student| student.account)
            .collect();
        assert_eq!(names, ["stillerBach", "neuerDachs"]);
        assert_eq!(
            count(
                &pool,
                "SELECT COUNT(*) FROM progress WHERE account = 'klugeEule'"
            )
            .await,
            1,
            "only the copy of the other world is left"
        );
        for sql in [
            "SELECT COUNT(*) FROM trophies",
            "SELECT COUNT(*) FROM trophy_reports",
            "SELECT COUNT(*) FROM display_names",
        ] {
            assert_eq!(count(&pool, sql).await, 0, "{sql}");
        }
        let left: Vec<i64> = sqlx::query_scalar("SELECT time FROM protocol_entries ORDER BY time")
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(left, [3, 4], "lines of others that mention it stay");
        let kinds: Vec<String> = sqlx::query_scalar("SELECT kind FROM jobs")
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(kinds, [JOB_REMOVE_ACCOUNT]);

        assert_eq!(
            list(&pool).await.unwrap(),
            [Removal {
                time: 100,
                account: "klugeEule".to_owned(),
                group: "7b".to_owned(),
                by: Some("leitung".to_owned()),
            }]
        );
    }

    #[tokio::test]
    async fn a_deleted_name_is_never_rolled_again() {
        let (pool, first, _) = setup().await;
        note_removed(&pool, &first, 100, &removed("klugeEule", None))
            .await
            .unwrap();
        assert_eq!(list(&pool).await.unwrap()[0].by, None);
        assert!(students::is_known_name(&pool, "KLUGEEULE").await.unwrap());
        assert!(!students::is_known_name(&pool, "niemand").await.unwrap());
    }
}
