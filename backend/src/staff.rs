//! Accounts of teachers, looked after by the school administration.
//!
//! A teacher exists in every world, so every order goes to all of them.
//! The backend is the one place that gives out their passwords. It
//! works out what the engine stores of a password (see `srp`) and sends
//! every world the same, so a teacher has one password everywhere. The
//! worlds refuse to change such a password inside the game.
//! Students and teachers are kept apart: an account that was created as
//! the account of a student never counts as a teacher here, whatever a
//! world reports about its privileges.

use anyhow::Result;
use lep_protocol::web::{
    AccessSlip, ArrivalState, ChangeState, PasswordState, StaffAccount, StaffState, StaffWorld,
    WebAccessState,
};
use lep_protocol::world::{
    AccountsCreated, CreateAccounts, NewAccount, RemoveAccount, SetPassword, SetPasswordEntry,
    JOB_CREATE_ACCOUNTS, JOB_REMOVE_ACCOUNT, JOB_SET_PASSWORD, JOB_SET_PASSWORD_ENTRY,
};
use sqlx::{Row, Sqlite, SqlitePool, Transaction};

use crate::{clock, jobs, names, removals, srp, students};

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

/// A start password for a teacher: three times as long as the one of a
/// student, because this account can do more and many keep it. Whoever
/// reads what the worlds store of it shall not find it by trying.
fn roll_password() -> String {
    format!(
        "{}-{}-{}",
        names::roll_password(),
        names::roll_password(),
        names::roll_password()
    )
}

/// The order to create the account of a teacher in a world.
fn creation(name: &str, entry: &str, by: &str) -> Result<serde_json::Value> {
    Ok(serde_json::to_value(CreateAccounts {
        accounts: vec![NewAccount {
            name: name.to_owned(),
            password: None,
            entry: Some(entry.to_owned()),
        }],
        teacher: true,
        by: Some(by.to_owned()),
    })?)
}

/// Orders a new world to create the teachers there are, each with the
/// password they have everywhere. Teachers who are being deleted and
/// ones the admin made in the game are left out.
pub async fn bring_into(pool: &SqlitePool, world_id: &str) -> Result<()> {
    let rows = sqlx::query(
        "SELECT account, password_entry, created_by FROM staff_accounts
         WHERE state != 'refused' AND password_entry IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM jobs
                           WHERE jobs.subject = staff_accounts.account AND jobs.kind = ?
                             AND jobs.finished_at IS NULL)
         ORDER BY account",
    )
    .bind(JOB_REMOVE_ACCOUNT)
    .fetch_all(pool)
    .await?;
    for row in &rows {
        let account: String = row.get("account");
        let payload = creation(
            &account,
            &row.get::<String, _>("password_entry"),
            &row.get::<String, _>("created_by"),
        )?;
        jobs::add_about(
            pool,
            world_id,
            JOB_CREATE_ACCOUNTS,
            &payload,
            Some(&account),
        )
        .await?;
    }
    Ok(())
}

/// Has every world create the account of a teacher, with a start
/// password and the privileges of the bundle for teachers. The password
/// is in the returned slip and nowhere else: the worlds get what the
/// engine stores of it, the same in every world.
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
    let slip = AccessSlip {
        account: name.to_owned(),
        password: roll_password(),
    };
    let entry = srp::entry(&slip.account, &slip.password);
    sqlx::query(
        "INSERT INTO staff_accounts (account, state, created_at, created_by, password_entry)
         VALUES (?, 'creating', ?, ?, ?)",
    )
    .bind(name)
    .bind(clock::now())
    .bind(by)
    .bind(&entry)
    .execute(pool)
    .await?;
    let payload = creation(name, &entry, by)?;
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
    let worlds = world_ids(pool).await?;
    // A teacher who was created here gets the same entry in every world,
    // and new worlds get it later.
    let entry = srp::entry(&slip.account, &slip.password);
    let managed = sqlx::query(
        "UPDATE staff_accounts SET password_entry = ?
         WHERE account = ? AND password_entry IS NOT NULL",
    )
    .bind(&entry)
    .bind(&account)
    .execute(pool)
    .await?
    .rows_affected()
        > 0;
    if managed {
        // An older order that no world has fetched yet would only be
        // overwritten by this one.
        sqlx::query(
            "DELETE FROM jobs WHERE kind = ? AND subject = ?
               AND finished_at IS NULL AND delivered_at IS NULL",
        )
        .bind(JOB_SET_PASSWORD_ENTRY)
        .bind(&account)
        .execute(pool)
        .await?;
        let payload = serde_json::to_value(SetPasswordEntry {
            name: account.clone(),
            entry,
            by: by.to_owned(),
        })?;
        for world in &worlds {
            jobs::add_about(
                pool,
                world,
                JOB_SET_PASSWORD_ENTRY,
                &payload,
                Some(&account),
            )
            .await?;
        }
        return Ok(Ok((slip, worlds)));
    }
    // One the admin made in the game has a password of its own in every
    // world: each world hashes the new one for itself.
    let payload = serde_json::to_value(SetPassword {
        name: slip.account.clone(),
        password: slip.password.clone(),
        staff: true,
        by: Some(by.to_owned()),
    })?;
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
        "DELETE FROM jobs WHERE subject = ? AND kind = 'set_password_entry'",
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

/// What a world answered to the newest order of one kind.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Answer {
    /// The world has not answered yet.
    Open,
    /// It answered, with whether it did it and what it said.
    Given(bool, String),
}

/// Works out how far the account of a teacher is in one world.
/// @param creation The answer to the newest order to create it.
/// @param password The answer to the newest order for a new password.
fn arrival(creation: Option<&Answer>, password: Option<&Answer>) -> ArrivalState {
    match creation {
        None => ArrivalState::Missing,
        Some(Answer::Open) => ArrivalState::Waiting,
        // The world answers such an order with how many accounts it
        // created and how many it refused, here one or the other
        // (`mods/lep_bridge/game/accounts.lua`).
        Some(Answer::Given(ok, said)) if !ok || !said.starts_with("1 created") => {
            ArrivalState::Refused
        }
        Some(Answer::Given(..)) => match password {
            None | Some(Answer::Given(true, _)) => ArrivalState::Arrived,
            Some(Answer::Open) => ArrivalState::PasswordWaiting,
            Some(Answer::Given(false, _)) => ArrivalState::Refused,
        },
    }
}

/// Lists how far the account of a teacher is in every world, sorted by
/// the name of the group.
async fn arrivals(pool: &SqlitePool, account: &str) -> Result<Vec<StaffWorld>> {
    let rows = sqlx::query(
        "SELECT worlds.name,
                created.rowid IS NOT NULL AS created_any,
                created.finished_at IS NOT NULL AS created_done,
                created.ok AS created_ok, created.message AS created_said,
                password.rowid IS NOT NULL AS password_any,
                password.finished_at IS NOT NULL AS password_done,
                password.ok AS password_ok
         FROM worlds
         LEFT JOIN jobs AS created ON created.rowid =
             (SELECT MAX(rowid) FROM jobs
              WHERE world_id = worlds.id AND kind = ?2 AND subject = ?1)
         LEFT JOIN jobs AS password ON password.rowid =
             (SELECT MAX(rowid) FROM jobs
              WHERE world_id = worlds.id AND kind = ?3 AND subject = ?1)
         ORDER BY worlds.name COLLATE NOCASE",
    )
    .bind(account)
    .bind(JOB_CREATE_ACCOUNTS)
    .bind(JOB_SET_PASSWORD_ENTRY)
    .fetch_all(pool)
    .await?;
    let answer = |row: &sqlx::sqlite::SqliteRow, kind: &str, said: Option<String>| {
        if !row.get::<bool, _>(format!("{kind}_any").as_str()) {
            None
        } else if !row.get::<bool, _>(format!("{kind}_done").as_str()) {
            Some(Answer::Open)
        } else {
            Some(Answer::Given(
                row.get::<Option<bool>, _>(format!("{kind}_ok").as_str()) == Some(true),
                said.unwrap_or_default(),
            ))
        }
    };
    Ok(rows
        .iter()
        .map(|row| StaffWorld {
            group: row.get("name"),
            state: arrival(
                answer(row, "created", row.get("created_said")).as_ref(),
                answer(row, "password", None).as_ref(),
            ),
        })
        .collect())
}

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
                staff_accounts.password_entry IS NOT NULL AS managed,
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
        // Teachers who were created here get their password as an entry,
        // and only about them the worlds were ever asked.
        let managed: bool = row.get("managed");
        let worlds = if managed {
            arrivals(pool, &account).await?
        } else {
            Vec::new()
        };
        let kind = if managed {
            JOB_SET_PASSWORD_ENTRY
        } else {
            JOB_SET_PASSWORD
        };
        let (password, _) = order_state(pool, kind, &account).await?;
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
            worlds,
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

#[cfg(test)]
mod tests {
    use super::*;

    fn given(ok: bool, said: &str) -> Answer {
        Answer::Given(ok, said.to_owned())
    }

    #[test]
    fn tells_how_far_an_account_is_in_a_world() {
        let created = given(true, "1 created, 0 refused");
        assert_eq!(arrival(None, None), ArrivalState::Missing);
        assert_eq!(arrival(Some(&Answer::Open), None), ArrivalState::Waiting);
        assert_eq!(arrival(Some(&created), None), ArrivalState::Arrived);

        // The world took the order but not the account, or not even the
        // order.
        for refused in [
            given(true, "0 created, 1 refused"),
            given(false, "the order cannot be read"),
            given(false, ""),
            given(true, ""),
        ] {
            assert_eq!(arrival(Some(&refused), None), ArrivalState::Refused);
            // Whatever it said about a password after that.
            assert_eq!(
                arrival(Some(&refused), Some(&given(true, "set"))),
                ArrivalState::Refused
            );
        }

        assert_eq!(
            arrival(Some(&created), Some(&Answer::Open)),
            ArrivalState::PasswordWaiting
        );
        assert_eq!(
            arrival(Some(&created), Some(&given(true, "set"))),
            ArrivalState::Arrived
        );
        assert_eq!(
            arrival(Some(&created), Some(&given(false, "unmanaged"))),
            ArrivalState::Refused
        );
        // The account is not there yet: the password waits behind it.
        assert_eq!(
            arrival(Some(&Answer::Open), Some(&Answer::Open)),
            ArrivalState::Waiting
        );
    }
}
