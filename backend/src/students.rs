//! Accounts of students.
//!
//! A teacher rolls names for a group, may roll single ones again, and
//! then has the world create the accounts. The start passwords are made
//! up at that moment, handed to the teacher for the access slips and to
//! the world in a job, and kept nowhere else.

use anyhow::Result;
use lep_protocol::web::{AccessSlip, Student, StudentState};
use lep_protocol::world::{AccountsCreated, CreateAccounts, NewAccount, JOB_CREATE_ACCOUNTS};
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

/// Lists the accounts of the students of a group, by name.
pub async fn list(pool: &SqlitePool, world_id: &str) -> Result<Vec<Student>> {
    let rows = sqlx::query(
        "SELECT account, state FROM students WHERE world_id = ? ORDER BY account COLLATE NOCASE",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    Ok(rows
        .iter()
        .map(|row| Student {
            account: row.get("account"),
            state: state_of(row.get("state")),
        })
        .collect())
}

/// Returns true if a name is taken at the school: by a student, a
/// teacher or the school administration, in any letter case.
async fn is_taken(tx: &mut Transaction<'_, Sqlite>, name: &str) -> Result<bool> {
    let taken: Option<i64> = sqlx::query_scalar(
        "SELECT 1 FROM students WHERE account = ?1 COLLATE NOCASE
         UNION ALL SELECT 1 FROM teachers WHERE account = ?1 COLLATE NOCASE
         UNION ALL SELECT 1 FROM teacher_worlds WHERE account = ?1 COLLATE NOCASE
         UNION ALL SELECT 1 FROM school_admin_worlds WHERE account = ?1 COLLATE NOCASE
         LIMIT 1",
    )
    .bind(name)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(taken.is_some())
}

/// Rolls a name nobody has and stores it as a draft. Returns `None` if
/// no free name turned up.
async fn add_draft(tx: &mut Transaction<'_, Sqlite>, world_id: &str) -> Result<Option<String>> {
    for _ in 0..ROLLS {
        let name = names::roll_account_name();
        if is_taken(tx, &name).await? {
            continue;
        }
        sqlx::query(
            "INSERT INTO students (account, world_id, state, created_at) VALUES (?, ?, 'draft', ?)",
        )
        .bind(&name)
        .bind(world_id)
        .bind(clock::now())
        .execute(&mut **tx)
        .await?;
        return Ok(Some(name));
    }
    Ok(None)
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
/// name. Returns the new name.
pub async fn reroll(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
) -> Result<Result<String, DraftError>> {
    let mut tx = pool.begin().await?;
    let removed = sqlx::query(
        "DELETE FROM students WHERE account = ? AND world_id = ? AND state IN ('draft', 'refused')",
    )
    .bind(account)
    .bind(world_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if removed == 0 {
        return Ok(Err(DraftError::NotADraft));
    }
    let Some(name) = add_draft(&mut tx, world_id).await? else {
        return Ok(Err(DraftError::NoNames));
    };
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
        "SELECT account FROM students WHERE world_id = ? AND state = 'draft'
         ORDER BY account COLLATE NOCASE",
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

        let new = reroll(&pool, &first, &before[0]).await.unwrap().unwrap();
        let after = names_in(&pool, &first).await;
        assert_eq!(after.len(), 2);
        assert!(after.contains(&new));
        assert!(after.contains(&before[1]));
        assert!(!after.contains(&before[0]));

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
