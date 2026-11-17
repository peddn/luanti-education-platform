//! Logging in at the web application: a link by mail, then a session.
//!
//! There are no passwords. Who can read the mail of a confirmed address
//! is the teacher. A session lasts a fixed time and is checked against
//! the privilege with every request.

use anyhow::Result;
use sqlx::{Row, SqlitePool};

use crate::keys;
use crate::teachers::{self, MAIL_PAUSE_SECONDS};

/// How long the link of a login mail works.
pub const LINK_SECONDS: i64 = 15 * 60;
/// How long a session lasts, counted from the login. It is not extended.
pub const SESSION_SECONDS: i64 = 12 * 60 * 60;

const LINK_PREFIX: &str = "lepl_";
const SESSION_PREFIX: &str = "leps_";

/// A login link that has to go out by mail.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Link {
    pub account: String,
    pub to: String,
    pub token: String,
}

/// Makes a login link for the account an address belongs to. Returns
/// `None` if nobody may log in with this address right now: it is not a
/// confirmed address, the account holds the privilege in no world, or a
/// mail went out a moment ago. The caller tells nobody which.
pub async fn request_link(pool: &SqlitePool, email: &str, now: i64) -> Result<Option<Link>> {
    let Some(email) = teachers::normalize_email(email) else {
        return Ok(None);
    };
    let row = sqlx::query("SELECT account, last_login_mail_at FROM teachers WHERE email = ?")
        .bind(&email)
        .fetch_optional(pool)
        .await?;
    let Some(row) = row else {
        return Ok(None);
    };
    let account: String = row.get("account");
    let last_mail: Option<i64> = row.get("last_login_mail_at");
    if last_mail.is_some_and(|at| now - at < MAIL_PAUSE_SECONDS)
        || teachers::worlds_of(pool, &account).await?.is_empty()
    {
        return Ok(None);
    }

    let token = keys::random(LINK_PREFIX);
    let mut tx = pool.begin().await?;
    // A new link replaces the old ones.
    sqlx::query("DELETE FROM login_tokens WHERE account = ?")
        .bind(&account)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "INSERT INTO login_tokens (token_hash, account, created_at, expires_at)
         VALUES (?, ?, ?, ?)",
    )
    .bind(keys::hash(&token))
    .bind(&account)
    .bind(now)
    .bind(now + LINK_SECONDS)
    .execute(&mut *tx)
    .await?;
    sqlx::query("UPDATE teachers SET last_login_mail_at = ? WHERE account = ?")
        .bind(now)
        .bind(&account)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Some(Link {
        account,
        to: email,
        token,
    }))
}

/// A session that was just started.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Started {
    pub account: String,
    /// The token for the cookie. It is not stored and cannot be read
    /// again.
    pub token: String,
}

/// Turns the token of a login link into a session. A link works once.
/// Returns `None` if the token is unknown, used or too old, or if the
/// account lost the privilege in the meantime.
pub async fn redeem(pool: &SqlitePool, token: &str, now: i64) -> Result<Option<Started>> {
    let hash = keys::hash(token);
    let mut tx = pool.begin().await?;
    let account: Option<String> = sqlx::query_scalar(
        "SELECT account FROM login_tokens WHERE token_hash = ? AND expires_at > ?",
    )
    .bind(&hash)
    .bind(now)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(account) = account else {
        return Ok(None);
    };
    sqlx::query("DELETE FROM login_tokens WHERE token_hash = ?")
        .bind(&hash)
        .execute(&mut *tx)
        .await?;
    let allowed: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM teacher_worlds WHERE account = ? LIMIT 1")
            .bind(&account)
            .fetch_optional(&mut *tx)
            .await?;
    if allowed.is_none() {
        // The link is used up all the same.
        tx.commit().await?;
        return Ok(None);
    }
    let session = keys::random(SESSION_PREFIX);
    sqlx::query(
        "INSERT INTO sessions (token_hash, account, created_at, expires_at) VALUES (?, ?, ?, ?)",
    )
    .bind(keys::hash(&session))
    .bind(&account)
    .bind(now)
    .bind(now + SESSION_SECONDS)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Some(Started {
        account,
        token: session,
    }))
}

/// Who a session belongs to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoggedIn {
    pub account: String,
    /// The confirmed address of the teacher.
    pub email: String,
    /// When the session ends, in seconds since 1970 (UTC).
    pub expires_at: i64,
}

/// Returns who is logged in with a session token, or `None` if the
/// session is unknown or over, or the account holds the privilege in no
/// world any more.
pub async fn find_session(pool: &SqlitePool, token: &str, now: i64) -> Result<Option<LoggedIn>> {
    let row = sqlx::query(
        "SELECT sessions.account AS account, teachers.email AS email,
                sessions.expires_at AS expires_at
         FROM sessions JOIN teachers ON teachers.account = sessions.account
         WHERE sessions.token_hash = ? AND sessions.expires_at > ?
           AND teachers.email IS NOT NULL
           AND EXISTS (SELECT 1 FROM teacher_worlds
                       WHERE teacher_worlds.account = sessions.account)",
    )
    .bind(keys::hash(token))
    .bind(now)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|row| LoggedIn {
        account: row.get("account"),
        email: row.get("email"),
        expires_at: row.get("expires_at"),
    }))
}

/// Ends a session. An unknown token changes nothing.
pub async fn end_session(pool: &SqlitePool, token: &str) -> Result<()> {
    sqlx::query("DELETE FROM sessions WHERE token_hash = ?")
        .bind(keys::hash(token))
        .execute(pool)
        .await?;
    Ok(())
}

/// Deletes links and sessions whose time is over. Returns how many rows
/// went.
pub async fn clean_up(pool: &SqlitePool, now: i64) -> Result<u64> {
    let links = sqlx::query("DELETE FROM login_tokens WHERE expires_at <= ?")
        .bind(now)
        .execute(pool)
        .await?
        .rows_affected();
    let sessions = sqlx::query("DELETE FROM sessions WHERE expires_at <= ?")
        .bind(now)
        .execute(pool)
        .await?
        .rows_affected();
    Ok(links + sessions)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, worlds};
    use lep_protocol::world::{WebAccessAction, WebAccessRequest};

    const EMAIL: &str = "anna@schule.example";

    /// A database with one world and a teacher with a confirmed address.
    async fn setup() -> (SqlitePool, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        teachers::set_holders(&pool, &world.id, &["lehrer1".to_owned()])
            .await
            .unwrap();
        confirm_address(&pool, "lehrer1", EMAIL).await;
        (pool, world.id)
    }

    async fn confirm_address(pool: &SqlitePool, account: &str, email: &str) {
        let request = WebAccessRequest {
            account: account.to_owned(),
            action: WebAccessAction::Set,
            email: Some(email.to_owned()),
        };
        let Some(teachers::Change::Mail { token, .. }) =
            teachers::request(pool, &request, 0).await.unwrap()
        else {
            panic!("expected a mail");
        };
        teachers::confirm(pool, &token, 1).await.unwrap().unwrap();
    }

    async fn log_in(pool: &SqlitePool, now: i64) -> String {
        let link = request_link(pool, EMAIL, now).await.unwrap().unwrap();
        redeem(pool, &link.token, now).await.unwrap().unwrap().token
    }

    #[tokio::test]
    async fn a_link_leads_to_a_session() {
        let (pool, _) = setup().await;
        let link = request_link(&pool, " Anna@Schule.Example ", 1000)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(link.account, "lehrer1");
        assert_eq!(link.to, EMAIL);
        assert!(link.token.starts_with(LINK_PREFIX));

        let started = redeem(&pool, &link.token, 1100).await.unwrap().unwrap();
        assert_eq!(started.account, "lehrer1");
        assert!(started.token.starts_with(SESSION_PREFIX));

        let who = find_session(&pool, &started.token, 1200)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(who.account, "lehrer1");
        assert_eq!(who.email, EMAIL);
        assert_eq!(who.expires_at, 1100 + SESSION_SECONDS);

        // A link works once, and it is no session token.
        assert_eq!(redeem(&pool, &link.token, 1300).await.unwrap(), None);
        assert_eq!(find_session(&pool, &link.token, 1300).await.unwrap(), None);
    }

    #[tokio::test]
    async fn nobody_else_gets_a_link() {
        let (pool, _) = setup().await;
        for email in ["fremd@schule.example", "no address", ""] {
            assert_eq!(request_link(&pool, email, 1000).await.unwrap(), None);
        }
        // An address that waits for its confirmation is not one yet.
        let request = WebAccessRequest {
            account: "lehrer1".to_owned(),
            action: WebAccessAction::Set,
            email: Some("neu@schule.example".to_owned()),
        };
        teachers::request(&pool, &request, 500).await.unwrap();
        assert_eq!(
            request_link(&pool, "neu@schule.example", 1000)
                .await
                .unwrap(),
            None
        );
        assert!(request_link(&pool, EMAIL, 1000).await.unwrap().is_some());
    }

    #[tokio::test]
    async fn links_get_too_old_and_a_new_one_replaces_the_old() {
        let (pool, _) = setup().await;
        let first = request_link(&pool, EMAIL, 1000).await.unwrap().unwrap();
        // Too soon for another mail.
        assert_eq!(request_link(&pool, EMAIL, 1030).await.unwrap(), None);
        let second = request_link(&pool, EMAIL, 1000 + MAIL_PAUSE_SECONDS)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(redeem(&pool, &first.token, 1100).await.unwrap(), None);

        let late = 1000 + MAIL_PAUSE_SECONDS + LINK_SECONDS;
        assert_eq!(redeem(&pool, &second.token, late).await.unwrap(), None);
        assert!(redeem(&pool, &second.token, late - 1)
            .await
            .unwrap()
            .is_some());
        assert_eq!(redeem(&pool, "lepl_made_up", 1100).await.unwrap(), None);
    }

    #[tokio::test]
    async fn a_session_ends_after_its_time_and_is_not_extended() {
        let (pool, _) = setup().await;
        let session = log_in(&pool, 1000).await;
        let last = 1000 + SESSION_SECONDS - 1;
        assert!(find_session(&pool, &session, last).await.unwrap().is_some());
        assert_eq!(find_session(&pool, &session, last + 1).await.unwrap(), None);
        assert_eq!(
            find_session(&pool, "leps_made_up", 1000).await.unwrap(),
            None
        );
    }

    #[tokio::test]
    async fn logging_out_ends_one_session() {
        let (pool, _) = setup().await;
        let first = log_in(&pool, 1000).await;
        let second = log_in(&pool, 2000).await;
        end_session(&pool, &first).await.unwrap();
        end_session(&pool, "leps_made_up").await.unwrap();
        assert_eq!(find_session(&pool, &first, 2100).await.unwrap(), None);
        assert!(find_session(&pool, &second, 2100).await.unwrap().is_some());
    }

    #[tokio::test]
    async fn without_the_privilege_everything_is_blocked_at_once() {
        let (pool, world) = setup().await;
        let session = log_in(&pool, 1000).await;
        let link = request_link(&pool, EMAIL, 2000).await.unwrap().unwrap();

        teachers::set_holders(&pool, &world, &[]).await.unwrap();
        assert_eq!(find_session(&pool, &session, 2100).await.unwrap(), None);
        assert_eq!(redeem(&pool, &link.token, 2100).await.unwrap(), None);
        assert_eq!(request_link(&pool, EMAIL, 3000).await.unwrap(), None);

        // With the privilege back, the session that is still running
        // counts again, and the used link stays used.
        teachers::set_holders(&pool, &world, &["lehrer1".to_owned()])
            .await
            .unwrap();
        assert!(find_session(&pool, &session, 3100).await.unwrap().is_some());
        assert_eq!(redeem(&pool, &link.token, 3100).await.unwrap(), None);
    }

    #[tokio::test]
    async fn removing_the_web_access_ends_all_sessions() {
        let (pool, _) = setup().await;
        let session = log_in(&pool, 1000).await;
        let link = request_link(&pool, EMAIL, 2000).await.unwrap().unwrap();
        let remove = WebAccessRequest {
            account: "lehrer1".to_owned(),
            action: WebAccessAction::Remove,
            email: None,
        };
        teachers::request(&pool, &remove, 2100).await.unwrap();
        assert_eq!(find_session(&pool, &session, 2200).await.unwrap(), None);
        assert_eq!(redeem(&pool, &link.token, 2200).await.unwrap(), None);
    }

    #[tokio::test]
    async fn cleaning_up_deletes_what_is_over() {
        let (pool, _) = setup().await;
        let session = log_in(&pool, 1000).await;
        request_link(&pool, EMAIL, 2000).await.unwrap().unwrap();
        assert_eq!(clean_up(&pool, 2100).await.unwrap(), 0);
        assert_eq!(clean_up(&pool, 2000 + LINK_SECONDS).await.unwrap(), 1);
        assert_eq!(clean_up(&pool, 1000 + SESSION_SECONDS).await.unwrap(), 1);
        assert_eq!(find_session(&pool, &session, 1500).await.unwrap(), None);
    }
}
