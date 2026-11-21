//! One password for a teacher in all worlds.
//!
//! A world stores of a password only an entry: a salt and a verifier.
//! The password cannot be worked out from it. The worlds report the
//! entries of their teachers, and the backend passes a new one on to
//! the other worlds. That is also how a teacher arrives in a world that
//! was created later.
//!
//! Reports and orders cross each other, so the passwords of a teacher
//! are counted. A world says which version its entry is built on and
//! whether it was changed there since. Only a change on top of the
//! newest version counts as a new password; everything older is brought
//! in step instead. No entry is ever written into a log.

use std::collections::BTreeSet;

use anyhow::Result;
use lep_protocol::world::{
    CreateAccounts, NewAccount, SetPasswordEntry, StaffPassword, StaffPasswords,
    JOB_CREATE_ACCOUNTS, JOB_REMOVE_ACCOUNT, JOB_SET_PASSWORD, JOB_SET_PASSWORD_ENTRY,
};
use sqlx::{Row, SqlitePool};

use crate::jobs;

/// Longest entry the backend takes. The engine writes about 370
/// characters.
const MAX_ENTRY: usize = 600;

/// Returns true if a text looks like what the engine stores of a
/// password: "#1#", a salt and a verifier, both in base64.
fn is_entry(text: &str) -> bool {
    let Some(rest) = text.strip_prefix("#1#") else {
        return false;
    };
    let part = |part: &str| {
        let body = part.trim_end_matches('=');
        !body.is_empty()
            && part.len() - body.len() <= 2
            && body
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '/')
    };
    text.len() <= MAX_ENTRY
        && matches!(rest.split_once('#'), Some((salt, verifier)) if part(salt) && part(verifier))
}

/// A teacher as the backend keeps them.
struct Kept {
    account: String,
    entry: Option<String>,
    version: u32,
    created_by: String,
}

/// Forgets the entry of a teacher, because every world is about to get
/// a new start password. Returns the new version, or `None` if the
/// account was not created here: then its password is not kept in step.
pub async fn start_over(pool: &SqlitePool, account: &str) -> Result<Option<u32>> {
    let version: Option<u32> = sqlx::query_scalar(
        "UPDATE staff_accounts SET password_entry = NULL, password_version = password_version + 1
         WHERE account = ? RETURNING password_version",
    )
    .bind(account)
    .fetch_optional(pool)
    .await?;
    if version.is_some() {
        drop_waiting(pool, account).await?;
        sqlx::query("UPDATE staff_worlds SET in_step = 0 WHERE account = ?")
            .bind(account)
            .execute(pool)
            .await?;
    }
    Ok(version)
}

/// Deletes the orders to write an entry that no world has fetched yet.
/// They carry an entry that does not count any more.
async fn drop_waiting(pool: &SqlitePool, account: &str) -> Result<()> {
    sqlx::query(
        "DELETE FROM jobs WHERE kind = ? AND subject = ?
           AND finished_at IS NULL AND delivered_at IS NULL",
    )
    .bind(JOB_SET_PASSWORD_ENTRY)
    .bind(account)
    .execute(pool)
    .await?;
    Ok(())
}

/// Returns true if a world has an order of one kind about an account
/// that it has not answered yet.
async fn is_waiting(pool: &SqlitePool, world_id: &str, kind: &str, account: &str) -> Result<bool> {
    let waiting: Option<i64> = sqlx::query_scalar(
        "SELECT 1 FROM jobs WHERE world_id = ? AND kind = ? AND subject = ?
           AND finished_at IS NULL LIMIT 1",
    )
    .bind(world_id)
    .bind(kind)
    .bind(account)
    .fetch_optional(pool)
    .await?;
    Ok(waiting.is_some())
}

/// Returns true if a world may say what the password of a teacher is
/// while the backend knows none: it has done what it was last told
/// about the account. A world that refused to create the account has
/// one of somebody else under that name.
async fn may_name_entry(pool: &SqlitePool, world_id: &str, account: &str) -> Result<bool> {
    let newest: Option<Option<bool>> = sqlx::query_scalar(
        "SELECT ok FROM jobs WHERE world_id = ?1 AND subject = ?2 AND kind IN (?3, ?4)
         ORDER BY created_at DESC, rowid DESC LIMIT 1",
    )
    .bind(world_id)
    .bind(account)
    .bind(JOB_CREATE_ACCOUNTS)
    .bind(JOB_SET_PASSWORD)
    .fetch_optional(pool)
    .await?;
    Ok(matches!(newest, None | Some(Some(true))))
}

async fn order_entry(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
    entry: &str,
    version: u32,
) -> Result<()> {
    let payload = serde_json::to_value(SetPasswordEntry {
        name: account.to_owned(),
        entry: entry.to_owned(),
        version,
    })?;
    jobs::add_about(
        pool,
        world_id,
        JOB_SET_PASSWORD_ENTRY,
        &payload,
        Some(account),
    )
    .await?;
    Ok(())
}

/// Stores a new entry for a teacher and orders every world that has the
/// account to write it. Returns the worlds to wake.
/// @param tell_origin True if the world it comes from is told as well,
///   so it learns the new version.
async fn pass_on(
    pool: &SqlitePool,
    from: &str,
    account: &str,
    entry: &str,
    version: u32,
    tell_origin: bool,
) -> Result<Vec<String>> {
    sqlx::query(
        "UPDATE staff_accounts SET password_entry = ?, password_version = ? WHERE account = ?",
    )
    .bind(entry)
    .bind(version)
    .bind(account)
    .execute(pool)
    .await?;
    drop_waiting(pool, account).await?;
    sqlx::query("UPDATE staff_worlds SET in_step = (world_id = ?) WHERE account = ?")
        .bind(from)
        .bind(account)
        .execute(pool)
        .await?;
    let worlds: Vec<String> = sqlx::query_scalar(
        "SELECT world_id FROM staff_worlds WHERE account = ?1 AND (?2 OR world_id != ?3)",
    )
    .bind(account)
    .bind(tell_origin)
    .bind(from)
    .fetch_all(pool)
    .await?;
    for world in &worlds {
        order_entry(pool, world, account, entry, version).await?;
    }
    Ok(worlds)
}

/// Takes in what a world stores of the passwords of its teachers.
/// Returns the worlds that got an order and shall be woken.
///
/// Only accounts the school administration created here are looked at.
/// Whatever else a world reports is dropped unread.
pub async fn note(
    pool: &SqlitePool,
    world_id: &str,
    report: &StaffPasswords,
) -> Result<BTreeSet<String>> {
    let rows = sqlx::query(
        "SELECT account, password_entry, password_version, created_by FROM staff_accounts
         WHERE state != 'refused'
           AND NOT EXISTS (SELECT 1 FROM students
                           WHERE students.account = staff_accounts.account COLLATE NOCASE)
           AND NOT EXISTS (SELECT 1 FROM jobs
                           WHERE jobs.subject = staff_accounts.account AND jobs.kind = ?
                             AND jobs.finished_at IS NULL)",
    )
    .bind(JOB_REMOVE_ACCOUNT)
    .fetch_all(pool)
    .await?;
    let mut wake = BTreeSet::new();
    for row in &rows {
        let kept = Kept {
            account: row.get("account"),
            entry: row.get("password_entry"),
            version: row.get("password_version"),
            created_by: row.get("created_by"),
        };
        let reported = report
            .accounts
            .iter()
            .find(|reported| reported.name == kept.account);
        match reported {
            Some(reported) => {
                wake.extend(note_present(pool, world_id, kept, reported).await?);
            }
            None => {
                if note_missing(pool, world_id, &kept).await? {
                    wake.insert(world_id.to_owned());
                }
            }
        }
    }
    Ok(wake)
}

/// A world has the account of a teacher.
async fn note_present(
    pool: &SqlitePool,
    world_id: &str,
    mut kept: Kept,
    reported: &StaffPassword,
) -> Result<Vec<String>> {
    // A backend that was set up again counts from the start, the worlds
    // do not: it catches up.
    if reported.version > kept.version {
        kept.version = reported.version;
        sqlx::query("UPDATE staff_accounts SET password_version = ? WHERE account = ?")
            .bind(kept.version)
            .bind(&kept.account)
            .execute(pool)
            .await?;
    }
    let newest = reported.version == kept.version;
    // A world that names no entry has one that never leaves it: nobody
    // has logged in there with the account yet.
    let named = reported.entry.as_deref().filter(|entry| is_entry(entry));
    let same = named.is_some() && kept.entry.as_deref() == named;
    sqlx::query(
        "INSERT INTO staff_worlds (world_id, account, in_step) VALUES (?1, ?2, ?3)
         ON CONFLICT (world_id, account) DO UPDATE SET in_step = ?3",
    )
    .bind(world_id)
    .bind(&kept.account)
    .bind(same)
    .execute(pool)
    .await?;

    if same {
        // The world has the right password but does not know its
        // version. Without it, a later change there would look old.
        if (!newest || reported.changed)
            && !is_waiting(pool, world_id, JOB_SET_PASSWORD_ENTRY, &kept.account).await?
        {
            if let Some(entry) = &kept.entry {
                order_entry(pool, world_id, &kept.account, entry, kept.version).await?;
                return Ok(vec![world_id.to_owned()]);
            }
        }
        return Ok(Vec::new());
    }
    if let (Some(entry), true, true) = (named, newest, reported.changed) {
        // Somebody chose a new password in this world, or logged in for
        // the first time.
        return pass_on(pool, world_id, &kept.account, entry, kept.version + 1, true).await;
    }
    let Some(entry) = &kept.entry else {
        // Every world got a start password and hashed it for itself.
        // The first one that has done so names the entry for all.
        if let (Some(named), true) = (named, newest) {
            if may_name_entry(pool, world_id, &kept.account).await? {
                return pass_on(pool, world_id, &kept.account, named, kept.version, false).await;
            }
        }
        return Ok(Vec::new());
    };
    // The world is behind.
    if is_waiting(pool, world_id, JOB_SET_PASSWORD_ENTRY, &kept.account).await? {
        return Ok(Vec::new());
    }
    order_entry(pool, world_id, &kept.account, entry, kept.version).await?;
    Ok(vec![world_id.to_owned()])
}

/// A world does not have the account of a teacher, or does not count it
/// as one. A world that was never asked to create it is asked now, with
/// the password the teacher has everywhere else. Returns true if it was.
async fn note_missing(pool: &SqlitePool, world_id: &str, kept: &Kept) -> Result<bool> {
    sqlx::query("DELETE FROM staff_worlds WHERE world_id = ? AND account = ?")
        .bind(world_id)
        .bind(&kept.account)
        .execute(pool)
        .await?;
    let Some(entry) = &kept.entry else {
        return Ok(false);
    };
    let asked: Option<i64> = sqlx::query_scalar(
        "SELECT 1 FROM jobs WHERE world_id = ? AND kind = ? AND subject = ? LIMIT 1",
    )
    .bind(world_id)
    .bind(JOB_CREATE_ACCOUNTS)
    .bind(&kept.account)
    .fetch_optional(pool)
    .await?;
    if asked.is_some() {
        return Ok(false);
    }
    let payload = serde_json::to_value(CreateAccounts {
        accounts: vec![NewAccount {
            name: kept.account.clone(),
            password: None,
            entry: Some(entry.clone()),
        }],
        teacher: true,
        by: Some(kept.created_by.clone()),
        version: Some(kept.version),
    })?;
    jobs::add_about(
        pool,
        world_id,
        JOB_CREATE_ACCOUNTS,
        &payload,
        Some(&kept.account),
    )
    .await?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn knows_the_entries_of_the_engine() {
        assert!(is_entry("#1#c2FsdA#dmVyaWZpZXI"));
        assert!(is_entry("#1#c2FsdA==#dmVyaWZpZXI="));
        assert!(is_entry("#1#a+b/c#d"));
        for wrong in [
            "",
            "#1#",
            "#1##abc",
            "#1#abc#",
            "#1#abc",
            "#2#abc#def",
            "abc#def",
            "#1#abc#def#ghi",
            "#1#a b#def",
            "#1#abc#de\nf",
            "#1#abc===#def",
            "#1#=#def",
        ] {
            assert!(!is_entry(wrong), "{wrong}");
        }
        assert!(!is_entry(&format!("#1#abc#{}", "a".repeat(MAX_ENTRY))));
    }
}
