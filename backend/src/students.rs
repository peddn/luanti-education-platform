//! Accounts of students.
//!
//! A teacher rolls names for a group, may roll single ones again, and
//! then has the world create the accounts. The start passwords are made
//! up at that moment, handed to the teacher for the access slips and to
//! the world in a job, and kept nowhere else.

use crate::removals;
use anyhow::Result;
use lep_protocol::web::{AccessSlip, ChangeState, PasswordState, Student, StudentState};
use lep_protocol::world::{
    AccountsCreated, CreateAccounts, NewAccount, SetPassword, JOB_CREATE_ACCOUNTS, JOB_SET_PASSWORD,
};
use sqlx::{Row, Sqlite, SqlitePool, Transaction};

use crate::{clock, jobs, names};

/// Most names that can be rolled with one request.
pub const MAX_DRAFT: u32 = 40;
/// Most accounts of students in one group.
pub const MAX_GROUP: i64 = 120;

/// How often a name is rolled before giving up, when names get scarce.
const ROLLS: usize = 200;

fn state_text(state: StudentState) -> &'static str {
    match state {
        StudentState::Draft => "draft",
        StudentState::Creating => "creating",
        StudentState::Active => "active",
        StudentState::Refused => "refused",
    }
}

fn state_of(text: &str) -> StudentState {
    match text {
        "creating" => StudentState::Creating,
        "active" => StudentState::Active,
        "refused" => StudentState::Refused,
        _ => StudentState::Draft,
    }
}

/// Lists the accounts of the students of a group, in the order they
/// were rolled. The order never changes: a name that is rolled again
/// keeps its place, so a list on a screen does not jump.
pub async fn list(pool: &SqlitePool, world_id: &str) -> Result<Vec<Student>> {
    // The newest order for a new password says how far it is: not
    // answered yet, or refused by the world.
    let rows = sqlx::query(
        "SELECT students.account, students.state,
                (SELECT CASE WHEN jobs.finished_at IS NULL THEN 'pending'
                             WHEN jobs.ok = 0 THEN 'refused' END
                 FROM jobs
                 WHERE jobs.world_id = students.world_id AND jobs.kind = 'set_password'
                   AND jobs.subject = students.account
                 ORDER BY jobs.rowid DESC LIMIT 1) AS password,
                (SELECT CASE WHEN jobs.finished_at IS NULL THEN 'pending'
                             WHEN jobs.ok = 0 THEN 'refused' END
                 FROM jobs
                 WHERE jobs.world_id = students.world_id
                   AND jobs.kind IN ('remove_display_name', 'set_display_locked')
                   AND jobs.subject = students.account
                 ORDER BY jobs.finished_at IS NULL DESC, jobs.rowid DESC LIMIT 1) AS display_change,
                (SELECT CASE WHEN jobs.ok = 0 THEN 'refused' ELSE 'pending' END
                 FROM jobs
                 WHERE jobs.world_id = students.world_id AND jobs.kind = 'remove_account'
                   AND jobs.subject = students.account
                 ORDER BY jobs.finished_at IS NULL DESC, jobs.rowid DESC LIMIT 1) AS removal,
                (SELECT jobs.message FROM jobs
                 WHERE jobs.world_id = students.world_id AND jobs.kind = 'remove_account'
                   AND jobs.subject = students.account
                 ORDER BY jobs.finished_at IS NULL DESC, jobs.rowid DESC LIMIT 1) AS removal_message,
                students.used AS used,
                display_names.name AS display_name,
                display_names.changed_at AS display_changed_at,
                COALESCE(display_names.locked, 0) AS display_locked
         FROM students
         LEFT JOIN display_names ON display_names.world_id = students.world_id
                                AND display_names.account = students.account
         WHERE students.world_id = ? ORDER BY students.rowid",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    Ok(rows
        .iter()
        .map(|row| {
            let removal: Option<String> = row.get("removal");
            Student {
                account: row.get("account"),
                state: state_of(row.get("state")),
                password: match row.get::<Option<String>, _>("password").as_deref() {
                    Some("pending") => Some(PasswordState::Pending),
                    Some("refused") => Some(PasswordState::Refused),
                    _ => None,
                },
                display_name: row.get("display_name"),
                display_changed_at: row.get("display_changed_at"),
                display_locked: row.get("display_locked"),
                // An order that waits counts before one that was refused.
                display_change: match row.get::<Option<String>, _>("display_change").as_deref() {
                    Some("pending") => Some(ChangeState::Pending),
                    Some("refused") => Some(ChangeState::Refused),
                    _ => None,
                },
                used: row.get("used"),
                // A world that has deleted and whose report is still on its
                // way counts as waiting: the account is shown until then.
                removal: match removal.as_deref() {
                    Some("pending") => Some(ChangeState::Pending),
                    Some("refused") => Some(ChangeState::Refused),
                    _ => None,
                },
                removal_refusal: (removal.as_deref() == Some("refused")).then(|| {
                    removals::refusal_of(
                        row.get::<Option<String>, _>("removal_message")
                            .as_deref()
                            .unwrap_or_default(),
                    )
                }),
            }
        })
        .collect())
}

const TAKEN: &str = "SELECT 1 FROM students WHERE account = ?1 COLLATE NOCASE
         UNION ALL SELECT 1 FROM teachers WHERE account = ?1 COLLATE NOCASE
         UNION ALL SELECT 1 FROM teacher_worlds WHERE account = ?1 COLLATE NOCASE
         UNION ALL SELECT 1 FROM school_admin_worlds WHERE account = ?1 COLLATE NOCASE
         UNION ALL SELECT 1 FROM account_removals WHERE account = ?1 COLLATE NOCASE
         LIMIT 1";

/// Returns true if a name is taken at the school: by a student, a
/// teacher or the school administration, in any letter case. The name
/// of an account that was deleted on request stays taken for good, so
/// the note about it never points at somebody else.
async fn is_taken(tx: &mut Transaction<'_, Sqlite>, name: &str) -> Result<bool> {
    let taken: Option<i64> = sqlx::query_scalar(TAKEN)
        .bind(name)
        .fetch_optional(&mut **tx)
        .await?;
    Ok(taken.is_some())
}

/// Returns true if a name is taken at the school or was deleted there,
/// see `is_taken`.
pub async fn is_known_name(pool: &SqlitePool, name: &str) -> Result<bool> {
    let taken: Option<i64> = sqlx::query_scalar(TAKEN)
        .bind(name)
        .fetch_optional(pool)
        .await?;
    Ok(taken.is_some())
}

/// Rolls a name nobody has. Returns `None` if no free name turned up.
async fn roll_free(tx: &mut Transaction<'_, Sqlite>) -> Result<Option<String>> {
    for _ in 0..ROLLS {
        let name = names::roll_account_name();
        if !is_taken(tx, &name).await? {
            return Ok(Some(name));
        }
    }
    Ok(None)
}

/// Rolls a name nobody has and stores it as a draft at the end of the
/// group. Returns `None` if no free name turned up.
async fn add_draft(tx: &mut Transaction<'_, Sqlite>, world_id: &str) -> Result<Option<String>> {
    let Some(name) = roll_free(tx).await? else {
        return Ok(None);
    };
    sqlx::query(
        "INSERT INTO students (account, world_id, state, created_at) VALUES (?, ?, 'draft', ?)",
    )
    .bind(&name)
    .bind(world_id)
    .bind(clock::now())
    .execute(&mut **tx)
    .await?;
    Ok(Some(name))
}

/// Why names could not be rolled or changed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DraftError {
    /// The count is zero or more than one request allows.
    BadCount,
    /// The group would get more accounts than a group may have.
    GroupFull,
    /// No free name turned up.
    NoNames,
    /// There is no such account in this group, or it is past the draft.
    NotADraft,
}

/// Rolls names for new accounts of a group. Nothing happens in the world
/// yet. Either all names are added or none.
pub async fn draft(
    pool: &SqlitePool,
    world_id: &str,
    count: u32,
) -> Result<Result<(), DraftError>> {
    if count == 0 || count > MAX_DRAFT {
        return Ok(Err(DraftError::BadCount));
    }
    let mut tx = pool.begin().await?;
    let present: i64 = sqlx::query_scalar("SELECT count(*) FROM students WHERE world_id = ?")
        .bind(world_id)
        .fetch_one(&mut *tx)
        .await?;
    if present + i64::from(count) > MAX_GROUP {
        return Ok(Err(DraftError::GroupFull));
    }
    for _ in 0..count {
        if add_draft(&mut tx, world_id).await?.is_none() {
            return Ok(Err(DraftError::NoNames));
        }
    }
    tx.commit().await?;
    Ok(Ok(()))
}

/// Removes an account that does not exist in the world: a draft, or a
/// name the world refused.
pub async fn remove(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
) -> Result<Result<(), DraftError>> {
    let removed = sqlx::query(
        "DELETE FROM students WHERE account = ? AND world_id = ? AND state IN ('draft', 'refused')",
    )
    .bind(account)
    .bind(world_id)
    .execute(pool)
    .await?
    .rows_affected();
    Ok(if removed > 0 {
        Ok(())
    } else {
        Err(DraftError::NotADraft)
    })
}

/// Replaces a draft, or a name the world refused, by a newly rolled
/// name, in the same place of the list. Returns the new name.
pub async fn reroll(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
) -> Result<Result<String, DraftError>> {
    let mut tx = pool.begin().await?;
    let changeable: Option<i64> = sqlx::query_scalar(
        "SELECT 1 FROM students
         WHERE account = ? AND world_id = ? AND state IN ('draft', 'refused')",
    )
    .bind(account)
    .bind(world_id)
    .fetch_optional(&mut *tx)
    .await?;
    if changeable.is_none() {
        return Ok(Err(DraftError::NotADraft));
    }
    let Some(name) = roll_free(&mut tx).await? else {
        return Ok(Err(DraftError::NoNames));
    };
    // The row stays, only its name changes: that keeps its place.
    sqlx::query(
        "UPDATE students SET account = ?, state = 'draft' WHERE account = ? AND world_id = ?",
    )
    .bind(&name)
    .bind(account)
    .bind(world_id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Ok(name))
}

/// Turns all drafts of a group into accounts: makes up a start password
/// for each, asks the world to create them and returns the access slips.
/// The passwords are in the returned slips and in the job for the world,
/// nowhere else. Returns the id of the job with the slips, or `None` if
/// there are no drafts.
pub async fn create(
    pool: &SqlitePool,
    world_id: &str,
) -> Result<Option<(String, Vec<AccessSlip>)>> {
    let mut tx = pool.begin().await?;
    let rows = sqlx::query(
        "SELECT account FROM students WHERE world_id = ? AND state = 'draft' ORDER BY rowid",
    )
    .bind(world_id)
    .fetch_all(&mut *tx)
    .await?;
    if rows.is_empty() {
        return Ok(None);
    }
    let slips: Vec<AccessSlip> = rows
        .iter()
        .map(|row| AccessSlip {
            account: row.get("account"),
            password: names::roll_password(),
        })
        .collect();
    sqlx::query("UPDATE students SET state = 'creating' WHERE world_id = ? AND state = 'draft'")
        .bind(world_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    let payload = CreateAccounts {
        accounts: slips
            .iter()
            .map(|slip| NewAccount {
                name: slip.account.clone(),
                password: slip.password.clone(),
            })
            .collect(),
    };
    let job = jobs::add(
        pool,
        world_id,
        JOB_CREATE_ACCOUNTS,
        &serde_json::to_value(payload)?,
    )
    .await?;
    Ok(Some((job, slips)))
}

/// Makes up a new start password for an account that exists in the
/// world, and asks the world to set it. The password is in the returned
/// slip and in the job for the world, nowhere else. Returns `None` if
/// the group has no such account that exists in the world.
pub async fn reset_password(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
) -> Result<Option<AccessSlip>> {
    // The name as it is stored: the engine tells letter cases apart.
    let stored: Option<String> = sqlx::query_scalar(
        "SELECT account FROM students WHERE account = ? AND world_id = ? AND state = 'active'",
    )
    .bind(account)
    .bind(world_id)
    .fetch_optional(pool)
    .await?;
    let Some(account) = stored else {
        return Ok(None);
    };
    let slip = AccessSlip {
        account: account.clone(),
        password: names::roll_password(),
    };
    let payload = SetPassword {
        name: slip.account.clone(),
        password: slip.password.clone(),
    };
    jobs::add_about(
        pool,
        world_id,
        JOB_SET_PASSWORD,
        &serde_json::to_value(payload)?,
        Some(&account),
    )
    .await?;
    Ok(Some(slip))
}

/// Notes what a world made of the accounts it was asked to create. Only
/// accounts of this world that wait for it change.
pub async fn note_created(
    pool: &SqlitePool,
    world_id: &str,
    report: &AccountsCreated,
) -> Result<()> {
    let mut tx = pool.begin().await?;
    for (names, state) in [
        (&report.created, StudentState::Active),
        (&report.refused, StudentState::Refused),
    ] {
        for name in names {
            sqlx::query(
                "UPDATE students SET state = ? WHERE account = ? AND world_id = ? AND state = 'creating'",
            )
            .bind(state_text(state))
            .bind(name)
            .bind(world_id)
            .execute(&mut *tx)
            .await?;
        }
    }
    tx.commit().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, teachers, worlds};
    use std::collections::HashSet;

    async fn setup() -> (SqlitePool, String, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (first, _) = worlds::add(&pool, "7b").await.unwrap();
        let (second, _) = worlds::add(&pool, "8a").await.unwrap();
        (pool, first.id, second.id)
    }

    async fn names_in(pool: &SqlitePool, world: &str) -> Vec<String> {
        list(pool, world)
            .await
            .unwrap()
            .into_iter()
            .map(|student| student.account)
            .collect()
    }

    async fn state(pool: &SqlitePool, world: &str, account: &str) -> StudentState {
        list(pool, world)
            .await
            .unwrap()
            .into_iter()
            .find(|student| student.account == account)
            .unwrap()
            .state
    }

    #[tokio::test]
    async fn rolls_names_that_are_free_at_the_whole_school() {
        let (pool, first, second) = setup().await;
        draft(&pool, &first, 30).await.unwrap().unwrap();
        draft(&pool, &second, 30).await.unwrap().unwrap();
        let mut all = names_in(&pool, &first).await;
        all.extend(names_in(&pool, &second).await);
        assert_eq!(all.len(), 60);
        let unique: HashSet<String> = all.iter().map(|name| name.to_lowercase()).collect();
        assert_eq!(unique.len(), 60);
        for student in list(&pool, &first).await.unwrap() {
            assert_eq!(student.state, StudentState::Draft);
        }
    }

    #[tokio::test]
    async fn a_name_of_a_teacher_is_taken_in_any_letter_case() {
        let (pool, first, _) = setup().await;
        let mut tx = pool.begin().await.unwrap();
        assert!(!is_taken(&mut tx, "klugeEule").await.unwrap());
        drop(tx);
        teachers::set_holders(&pool, &first, &["KlugeEule".to_owned()])
            .await
            .unwrap();
        crate::groups::set_school_admins(&pool, &first, &["mutigerDachs".to_owned()])
            .await
            .unwrap();
        let mut tx = pool.begin().await.unwrap();
        assert!(is_taken(&mut tx, "klugeEule").await.unwrap());
        assert!(is_taken(&mut tx, "MUTIGERDACHS").await.unwrap());
        assert!(!is_taken(&mut tx, "frohesReh").await.unwrap());
    }

    #[tokio::test]
    async fn refuses_counts_that_make_no_sense() {
        let (pool, first, _) = setup().await;
        assert_eq!(
            draft(&pool, &first, 0).await.unwrap(),
            Err(DraftError::BadCount)
        );
        assert_eq!(
            draft(&pool, &first, MAX_DRAFT + 1).await.unwrap(),
            Err(DraftError::BadCount)
        );
        for _ in 0..3 {
            draft(&pool, &first, MAX_DRAFT).await.unwrap().unwrap();
        }
        // Nothing is added by halves.
        assert_eq!(
            draft(&pool, &first, 1).await.unwrap(),
            Err(DraftError::GroupFull)
        );
        assert_eq!(names_in(&pool, &first).await.len(), MAX_GROUP as usize);
    }

    #[tokio::test]
    async fn a_draft_can_be_rolled_again_or_removed() {
        let (pool, first, second) = setup().await;
        draft(&pool, &first, 2).await.unwrap().unwrap();
        let before = names_in(&pool, &first).await;

        // The new name takes the place of the old one.
        let new = reroll(&pool, &first, &before[0]).await.unwrap().unwrap();
        assert_ne!(new, before[0]);
        assert_eq!(
            names_in(&pool, &first).await,
            vec![new.clone(), before[1].clone()]
        );

        remove(&pool, &first, &before[1]).await.unwrap().unwrap();
        assert_eq!(names_in(&pool, &first).await, vec![new.clone()]);

        // Not through another group, and not twice.
        assert_eq!(
            reroll(&pool, &second, &new).await.unwrap(),
            Err(DraftError::NotADraft)
        );
        assert_eq!(
            remove(&pool, &second, &new).await.unwrap(),
            Err(DraftError::NotADraft)
        );
        assert_eq!(
            remove(&pool, &first, &before[1]).await.unwrap(),
            Err(DraftError::NotADraft)
        );
    }

    #[tokio::test]
    async fn rolling_one_name_again_leaves_all_others_where_they_are() {
        let (pool, first, _) = setup().await;
        draft(&pool, &first, 6).await.unwrap().unwrap();
        for round in 0..120 {
            let before = names_in(&pool, &first).await;
            let place = round % before.len();
            let new = reroll(&pool, &first, &before[place])
                .await
                .unwrap()
                .unwrap();
            let mut expected = before.clone();
            expected[place] = new;
            assert_eq!(names_in(&pool, &first).await, expected, "round {round}");
        }
        // New names go to the end.
        let before = names_in(&pool, &first).await;
        draft(&pool, &first, 2).await.unwrap().unwrap();
        assert_eq!(names_in(&pool, &first).await[..6], before[..]);
    }

    #[tokio::test]
    async fn creating_hands_out_passwords_once_and_asks_the_world() {
        let (pool, first, _) = setup().await;
        assert_eq!(create(&pool, &first).await.unwrap(), None);
        draft(&pool, &first, 3).await.unwrap().unwrap();
        let drafted = names_in(&pool, &first).await;

        let (job, slips) = create(&pool, &first).await.unwrap().unwrap();
        assert_eq!(
            slips
                .iter()
                .map(|slip| slip.account.clone())
                .collect::<Vec<_>>(),
            drafted
        );
        for slip in &slips {
            assert_eq!(slip.password.split('-').count(), 3);
            assert_eq!(
                state(&pool, &first, &slip.account).await,
                StudentState::Creating
            );
        }

        // The world gets exactly these names and passwords.
        let waiting = jobs::take_waiting(&pool, &first).await.unwrap();
        assert_eq!(waiting.len(), 1);
        assert_eq!(waiting[0].id, job);
        assert_eq!(waiting[0].kind, JOB_CREATE_ACCOUNTS);
        let sent: CreateAccounts = serde_json::from_value(waiting[0].payload.clone()).unwrap();
        assert_eq!(sent.accounts.len(), 3);
        for (account, slip) in sent.accounts.iter().zip(&slips) {
            assert_eq!(
                (&account.name, &account.password),
                (&slip.account, &slip.password)
            );
        }

        // No second round for the same accounts, and nothing to change.
        assert_eq!(create(&pool, &first).await.unwrap(), None);
        assert_eq!(
            reroll(&pool, &first, &drafted[0]).await.unwrap(),
            Err(DraftError::NotADraft)
        );
        assert_eq!(
            remove(&pool, &first, &drafted[0]).await.unwrap(),
            Err(DraftError::NotADraft)
        );
    }

    /// A group with one account that exists in the world.
    async fn with_active_account() -> (SqlitePool, String, String, String) {
        let (pool, first, second) = setup().await;
        draft(&pool, &first, 2).await.unwrap().unwrap();
        let (job, slips) = create(&pool, &first).await.unwrap().unwrap();
        let report = AccountsCreated {
            created: vec![slips[0].account.clone()],
            refused: vec![],
        };
        note_created(&pool, &first, &report).await.unwrap();
        finish(&pool, &first, &job, true, "done").await.unwrap();
        (pool, first, second, slips[0].account.clone())
    }

    async fn finish(
        pool: &SqlitePool,
        world: &str,
        job: &str,
        ok: bool,
        message: &str,
    ) -> Result<bool> {
        let result = lep_protocol::world::JobResult {
            ok,
            message: message.to_owned(),
        };
        jobs::finish(pool, world, job, &result).await
    }

    async fn password_state(
        pool: &SqlitePool,
        world: &str,
        account: &str,
    ) -> Option<PasswordState> {
        list(pool, world)
            .await
            .unwrap()
            .into_iter()
            .find(|student| student.account == account)
            .unwrap()
            .password
    }

    #[tokio::test]
    async fn a_new_password_is_rolled_and_ordered_from_the_world() {
        let (pool, first, _, account) = with_active_account().await;
        assert_eq!(password_state(&pool, &first, &account).await, None);

        let slip = reset_password(&pool, &first, &account.to_uppercase())
            .await
            .unwrap()
            .unwrap();
        // The name goes out as it is stored, whatever was asked for.
        assert_eq!(slip.account, account);
        assert_eq!(slip.password.split('-').count(), 3);
        assert_eq!(
            password_state(&pool, &first, &account).await,
            Some(PasswordState::Pending)
        );

        let waiting = jobs::take_waiting(&pool, &first).await.unwrap();
        assert_eq!(waiting.len(), 1);
        assert_eq!(waiting[0].kind, JOB_SET_PASSWORD);
        let sent: SetPassword = serde_json::from_value(waiting[0].payload.clone()).unwrap();
        assert_eq!(
            (sent.name, sent.password),
            (slip.account, slip.password.clone())
        );

        // Done: nothing to show, and the password is gone from the database.
        finish(&pool, &first, &waiting[0].id, true, "set")
            .await
            .unwrap();
        assert_eq!(password_state(&pool, &first, &account).await, None);
        let stored: String = sqlx::query_scalar("SELECT payload FROM jobs WHERE id = ?")
            .bind(&waiting[0].id)
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(stored, "{}");
    }

    #[tokio::test]
    async fn a_refusal_of_the_world_is_shown_until_the_next_try() {
        let (pool, first, _, account) = with_active_account().await;
        reset_password(&pool, &first, &account)
            .await
            .unwrap()
            .unwrap();
        let job = jobs::take_waiting(&pool, &first).await.unwrap().remove(0);
        finish(&pool, &first, &job.id, false, "staff")
            .await
            .unwrap();
        assert_eq!(
            password_state(&pool, &first, &account).await,
            Some(PasswordState::Refused)
        );
        // The newest order counts.
        reset_password(&pool, &first, &account)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            password_state(&pool, &first, &account).await,
            Some(PasswordState::Pending)
        );
    }

    #[tokio::test]
    async fn only_accounts_that_exist_in_the_world_get_a_new_password() {
        let (pool, first, second, account) = with_active_account().await;
        // Still on its way into the world.
        let creating = names_in(&pool, &first)
            .await
            .into_iter()
            .find(|name| *name != account)
            .unwrap();
        draft(&pool, &first, 1).await.unwrap().unwrap();
        let drafted = names_in(&pool, &first).await.pop().unwrap();
        for name in [creating.as_str(), drafted.as_str(), "lehrer1", "niemand"] {
            assert_eq!(
                reset_password(&pool, &first, name).await.unwrap(),
                None,
                "{name}"
            );
        }
        // Not through another group.
        assert_eq!(
            reset_password(&pool, &second, &account).await.unwrap(),
            None
        );
        assert!(jobs::take_waiting(&pool, &first)
            .await
            .unwrap()
            .iter()
            .all(|job| job.kind != JOB_SET_PASSWORD));
    }

    #[tokio::test]
    async fn the_world_says_what_became_of_the_accounts() {
        let (pool, first, second) = setup().await;
        draft(&pool, &first, 3).await.unwrap().unwrap();
        draft(&pool, &second, 1).await.unwrap().unwrap();
        let (_, slips) = create(&pool, &first).await.unwrap().unwrap();
        let names: Vec<String> = slips.into_iter().map(|slip| slip.account).collect();
        let foreign = names_in(&pool, &second).await.remove(0);

        let report = AccountsCreated {
            created: vec![names[0].clone(), foreign.clone(), "nobody".to_owned()],
            refused: vec![names[1].clone()],
        };
        note_created(&pool, &first, &report).await.unwrap();
        assert_eq!(state(&pool, &first, &names[0]).await, StudentState::Active);
        assert_eq!(state(&pool, &first, &names[1]).await, StudentState::Refused);
        assert_eq!(
            state(&pool, &first, &names[2]).await,
            StudentState::Creating
        );
        // A world cannot touch the accounts of another group.
        assert_eq!(state(&pool, &second, &foreign).await, StudentState::Draft);

        // What exists stays, whatever a later report says.
        let late = AccountsCreated {
            created: vec![],
            refused: vec![names[0].clone()],
        };
        note_created(&pool, &first, &late).await.unwrap();
        assert_eq!(state(&pool, &first, &names[0]).await, StudentState::Active);

        // A refused name can be rolled again or removed.
        let new = reroll(&pool, &first, &names[1]).await.unwrap().unwrap();
        assert_eq!(state(&pool, &first, &new).await, StudentState::Draft);
    }
}
