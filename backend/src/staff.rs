//! Accounts of teachers, looked after by the school administration.
//!
//! A teacher exists in every world, so every order goes to all of them.
//! Students and teachers are kept apart: an account that was created as
//! the account of a student never counts as a teacher here, whatever a
//! world reports about its privileges.

use anyhow::Result;
use lep_protocol::web::{
    AccessSlip, ChangeState, PasswordState, StaffAccount, StaffState, WebAccessState,
};
use lep_protocol::world::{
    AccountsCreated, CreateAccounts, NewAccount, RemoveAccount, SetPassword, JOB_CREATE_ACCOUNTS,
    JOB_REMOVE_ACCOUNT, JOB_SET_PASSWORD,
};
use sqlx::{Row, Sqlite, SqlitePool, Transaction};

use crate::{clock, jobs, names, removals, students};

/// Shortest and longest name of a teacher. The engine takes 20
/// characters; the backend stays one below.
const MIN_NAME: usize = 2;
const MAX_NAME: usize = 19;

/// Why an order about the account of a teacher was not given.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StaffError {
    /// The name is too short, too long or holds other characters than
    /// letters, digits, `_` and `-`.
    InvalidName,
    /// The name is taken at the school, or was deleted there.
    Taken,
    /// There is no world that could create the account.
    NoWorld,
    /// There is no such teacher.
    NotFound,
    /// The account belongs to the school administration, or it is the
    /// own one: such accounts are never changed from here.
    Protected,
}

/// Returns the names in a list that are not accounts of students. What a
/// world reports about its teachers goes through here: a student never
/// becomes a teacher or a member of the school administration here,
/// whatever privilege was handed out in the game.
pub async fn without_students(
    tx: &mut Transaction<'_, Sqlite>,
    accounts: &[String],
) -> Result<Vec<String>> {
    let mut kept = Vec::with_capacity(accounts.len());
    for account in accounts {
        let student: Option<i64> =
            sqlx::query_scalar("SELECT 1 FROM students WHERE account = ? COLLATE NOCASE")
                .bind(account)
                .fetch_optional(&mut **tx)
                .await?;
        if student.is_none() {
            kept.push(account.clone());
        }
    }
    Ok(kept)
}

fn is_name(name: &str) -> bool {
    (MIN_NAME..=MAX_NAME).contains(&name.len())
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

async fn world_ids(pool: &SqlitePool) -> Result<Vec<String>> {
    Ok(sqlx::query_scalar("SELECT id FROM worlds ORDER BY name")
        .fetch_all(pool)
        .await?)
}

/// A start password for a teacher: twice as long as the one of a
/// student, because this account can do more.
fn roll_password() -> String {
    format!("{}-{}", names::roll_password(), names::roll_password())
}

/// Has every world create the account of a teacher, with a start
/// password and the privileges of the bundle for teachers. The password
/// is in the returned slip and in the jobs for the worlds, nowhere else.
/// Returns the slip and the worlds to wake.
/// @param by Account name of the member of the school administration.
pub async fn create(
    pool: &SqlitePool,
    name: &str,
    by: &str,
) -> Result<Result<(AccessSlip, Vec<String>), StaffError>> {
    let name = name.trim();
    if !is_name(name) {
        return Ok(Err(StaffError::InvalidName));
    }
    if students::is_known_name(pool, name).await? || is_listed(pool, name).await? {
        return Ok(Err(StaffError::Taken));
    }
    let worlds = world_ids(pool).await?;
    if worlds.is_empty() {
        return Ok(Err(StaffError::NoWorld));
    }
    sqlx::query(
        "INSERT INTO staff_accounts (account, state, created_at, created_by)
         VALUES (?, 'creating', ?, ?)",
    )
    .bind(name)
    .bind(clock::now())
    .bind(by)
    .execute(pool)
    .await?;
    let slip = AccessSlip {
        account: name.to_owned(),
        password: roll_password(),
    };
    let payload = serde_json::to_value(CreateAccounts {
        accounts: vec![NewAccount {
            name: slip.account.clone(),
            password: slip.password.clone(),
        }],
        teacher: true,
        by: Some(by.to_owned()),
    })?;
    for world in &worlds {
        jobs::add_about(pool, world, JOB_CREATE_ACCOUNTS, &payload, Some(name)).await?;
    }
    Ok(Ok((slip, worlds)))
}

async fn is_listed(pool: &SqlitePool, name: &str) -> Result<bool> {
    let found: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM staff_accounts WHERE account = ? COLLATE NOCASE")
            .bind(name)
            .fetch_optional(pool)
            .await?;
    Ok(found.is_some())
}

/// Notes what a world made of the accounts of teachers it was asked to
/// create. One world that has the account is enough.
pub async fn note_created(pool: &SqlitePool, report: &AccountsCreated) -> Result<()> {
    for name in &report.created {
        sqlx::query("UPDATE staff_accounts SET state = 'active' WHERE account = ?")
            .bind(name)
            .execute(pool)
            .await?;
    }
    for name in &report.refused {
        sqlx::query(
            "UPDATE staff_accounts SET state = 'refused' WHERE account = ? AND state = 'creating'",
        )
        .bind(name)
        .execute(pool)
        .await?;
    }
    Ok(())
}

/// Returns the name of a teacher as it is stored, if orders about the
/// account may be given: it is listed, it does not belong to the school
/// administration, and it is not the account of who asks.
async fn changeable(
    pool: &SqlitePool,
    account: &str,
    by: &str,
) -> Result<Result<String, StaffError>> {
    let stored: Option<String> = sqlx::query_scalar(
        "SELECT account FROM staff_accounts WHERE account = ?1 COLLATE NOCASE
         UNION SELECT account FROM teacher_worlds WHERE account = ?1
         LIMIT 1",
    )
    .bind(account)
    .fetch_optional(pool)
    .await?;
    let Some(stored) = stored else {
        return Ok(Err(StaffError::NotFound));
    };
    let admin: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM school_admin_worlds WHERE account = ? LIMIT 1")
            .bind(&stored)
            .fetch_optional(pool)
            .await?;
    if admin.is_some() || stored.eq_ignore_ascii_case(by) {
        return Ok(Err(StaffError::Protected));
    }
    Ok(Ok(stored))
}

/// Makes up a new start password for a teacher and asks every world to
/// set it. Returns the slip and the worlds to wake.
pub async fn reset_password(
    pool: &SqlitePool,
    account: &str,
    by: &str,
) -> Result<Result<(AccessSlip, Vec<String>), StaffError>> {
    let account = match changeable(pool, account, by).await? {
        Ok(account) => account,
        Err(error) => return Ok(Err(error)),
    };
    let slip = AccessSlip {
        account: account.clone(),
        password: roll_password(),
    };
    let payload = serde_json::to_value(SetPassword {
        name: slip.account.clone(),
        password: slip.password.clone(),
        staff: true,
        by: Some(by.to_owned()),
    })?;
    let worlds = world_ids(pool).await?;
    for world in &worlds {
        jobs::add_about(pool, world, JOB_SET_PASSWORD, &payload, Some(&account)).await?;
    }
    Ok(Ok((slip, worlds)))
}

/// Orders every world to delete the account of a teacher. An account
/// that was never created anywhere is dropped at once. Returns the
/// worlds to wake.
pub async fn remove(
    pool: &SqlitePool,
    account: &str,
    by: &str,
) -> Result<Result<Vec<String>, StaffError>> {
    let account = match changeable(pool, account, by).await? {
        Ok(account) => account,
        Err(error) => return Ok(Err(error)),
    };
    let refused: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM staff_accounts WHERE account = ? AND state = 'refused'")
            .bind(&account)
            .fetch_optional(pool)
            .await?;
    if refused.is_some() {
        forget(pool, &account).await?;
        return Ok(Ok(Vec::new()));
    }
    let payload = serde_json::to_value(RemoveAccount {
        account: account.clone(),
        only_unused: false,
        staff: true,
        by: by.to_owned(),
    })?;
    let worlds = world_ids(pool).await?;
    for world in &worlds {
        let waiting: Option<i64> = sqlx::query_scalar(
            "SELECT 1 FROM jobs WHERE world_id = ? AND kind = ? AND subject = ?
               AND finished_at IS NULL LIMIT 1",
        )
        .bind(world)
        .bind(JOB_REMOVE_ACCOUNT)
        .bind(&account)
        .fetch_optional(pool)
        .await?;
        if waiting.is_none() {
            jobs::add_about(pool, world, JOB_REMOVE_ACCOUNT, &payload, Some(&account)).await?;
        }
    }
    Ok(Ok(worlds))
}

/// Deletes what the backend keeps about a teacher beyond a single
/// world: the account here, the address, the web access with its
/// sessions, and the groups it was assigned to. Called when a world
/// reports that it deleted the account.
pub async fn forget(pool: &SqlitePool, account: &str) -> Result<()> {
    let mut tx = pool.begin().await?;
    for delete in [
        "DELETE FROM staff_accounts WHERE account = ?",
        // Tokens and sessions go with the row.
        "DELETE FROM teachers WHERE account = ?",
        "DELETE FROM group_teachers WHERE account = ?",
        "DELETE FROM jobs WHERE subject = ? AND kind = 'create_accounts'",
    ] {
        sqlx::query(delete).bind(account).execute(&mut *tx).await?;
    }
    tx.commit().await?;
    Ok(())
}

/// Takes the groups away from everybody who holds the privilege for web
/// access in no world any more. Called whenever a world reported its
/// teachers.
pub async fn drop_stale_assignments(tx: &mut Transaction<'_, Sqlite>) -> Result<()> {
    sqlx::query(
        "DELETE FROM group_teachers
         WHERE account NOT IN (SELECT account FROM teacher_worlds)",
    )
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// How the newest order of one kind about an account stands: asked in
/// every world, it waits while one has not answered, and it is refused
/// only if none of them did it.
const ORDER_STATE: &str = "SELECT CASE WHEN SUM(newest.finished_at IS NULL) > 0 THEN 'pending'
                    WHEN SUM(newest.ok = 1) = 0 THEN 'refused' END AS state,
               MIN(CASE WHEN newest.ok = 0 THEN newest.message END) AS message
        FROM jobs AS newest
        WHERE newest.kind = ?1 AND newest.subject = ?2
          AND newest.rowid = (SELECT MAX(other.rowid) FROM jobs AS other
                              WHERE other.kind = newest.kind AND other.subject = newest.subject
                                AND other.world_id = newest.world_id)";

async fn order_state(
    pool: &SqlitePool,
    kind: &str,
    account: &str,
) -> Result<(Option<String>, Option<String>)> {
    let row = sqlx::query(ORDER_STATE)
        .bind(kind)
        .bind(account)
        .fetch_one(pool)
        .await?;
    Ok((row.get("state"), row.get("message")))
}

/// Lists the accounts of all teachers: the ones that were created here,
/// and everybody a world reports as a teacher or as a member of the
/// school administration. Sorted by name.
pub async fn list(pool: &SqlitePool) -> Result<Vec<StaffAccount>> {
    let rows = sqlx::query(
        "SELECT names.account,
                staff_accounts.state AS state,
                EXISTS (SELECT 1 FROM teacher_worlds
                        WHERE teacher_worlds.account = names.account) AS holder,
                EXISTS (SELECT 1 FROM school_admin_worlds
                        WHERE school_admin_worlds.account = names.account) AS school_admin,
                teachers.email IS NOT NULL AS confirmed,
                teachers.pending_email IS NOT NULL AS pending
         FROM (SELECT account FROM staff_accounts
               UNION SELECT account FROM teacher_worlds
               UNION SELECT account FROM school_admin_worlds) AS names
         LEFT JOIN staff_accounts ON staff_accounts.account = names.account
         LEFT JOIN teachers ON teachers.account = names.account
         ORDER BY names.account COLLATE NOCASE",
    )
    .fetch_all(pool)
    .await?;
    let mut list = Vec::with_capacity(rows.len());
    for row in &rows {
        let account: String = row.get("account");
        let groups: Vec<String> = sqlx::query_scalar(
            "SELECT worlds.name FROM group_teachers
             JOIN worlds ON worlds.id = group_teachers.world_id
             WHERE group_teachers.account = ? ORDER BY worlds.name COLLATE NOCASE",
        )
        .bind(&account)
        .fetch_all(pool)
        .await?;
        let (password, _) = order_state(pool, JOB_SET_PASSWORD, &account).await?;
        let (removal, message) = order_state(pool, JOB_REMOVE_ACCOUNT, &account).await?;
        list.push(StaffAccount {
            state: match row.get::<Option<String>, _>("state").as_deref() {
                Some("creating") => Some(StaffState::Creating),
                Some("active") => Some(StaffState::Active),
                Some("refused") => Some(StaffState::Refused),
                _ => None,
            },
            holder: row.get("holder"),
            school_admin: row.get("school_admin"),
            web_access: if row.get::<bool, _>("confirmed") {
                WebAccessState::Confirmed
            } else if row.get::<bool, _>("pending") {
                WebAccessState::Pending
            } else {
                WebAccessState::None
            },
            groups,
            password: match password.as_deref() {
                Some("pending") => Some(PasswordState::Pending),
                Some("refused") => Some(PasswordState::Refused),
                _ => None,
            },
            removal: match removal.as_deref() {
                Some("pending") => Some(ChangeState::Pending),
                Some("refused") => Some(ChangeState::Refused),
                _ => None,
            },
            removal_refusal: (removal.as_deref() == Some("refused"))
                .then(|| removals::refusal_of(message.as_deref().unwrap_or_default())),
            account,
        });
    }
    Ok(list)
}
