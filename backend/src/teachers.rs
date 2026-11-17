//! Teachers and their web access.
//!
//! A teacher is an account name, across all worlds. The worlds say who
//! holds the privilege for web access; a teacher enters an address at
//! the desk and confirms it with a link from a mail.

use anyhow::Result;
use lep_protocol::world::{WebAccessAction, WebAccessRequest, WebAccessStatus};
use sqlx::{Row, SqlitePool};

use crate::keys;

/// How long the link of a confirmation mail works.
pub const TOKEN_SECONDS: i64 = 15 * 60;
/// Shortest time between two confirmation mails to the same address.
pub const MAIL_PAUSE_SECONDS: i64 = 60;

/// Longest account name that is taken in.
const MAX_ACCOUNT: usize = 60;
/// Longest address, as mail allows.
const MAX_EMAIL: usize = 254;
const TOKEN_PREFIX: &str = "lepc_";

/// Returns true if a text can be the account name of a player.
pub fn is_account(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= MAX_ACCOUNT
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// Returns an address as it is stored, trimmed and in lower case, or
/// `None` if the text cannot be an address. Whether mail arrives there
/// only the confirmation shows.
pub fn normalize_email(text: &str) -> Option<String> {
    let email = text.trim().to_lowercase();
    if email.len() > MAX_EMAIL || email.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return None;
    }
    let (local, domain) = email.split_once('@')?;
    let domain_ok = domain.contains('.')
        && !domain.contains('@')
        && domain.split('.').all(|part| !part.is_empty());
    (!local.is_empty() && domain_ok).then_some(email)
}

/// Shortens an address for showing it in a world: the first character
/// and the domain.
pub fn mask(email: &str) -> String {
    match email.split_once('@') {
        Some((local, domain)) => {
            let first: String = local.chars().take(1).collect();
            format!("{first}…@{domain}")
        }
        None => "…".to_owned(),
    }
}

/// Replaces the list of accounts that hold the privilege for web access
/// in a world. Names that cannot be accounts are left out.
pub async fn set_holders(pool: &SqlitePool, world_id: &str, accounts: &[String]) -> Result<()> {
    let mut tx = pool.begin().await?;
    sqlx::query("DELETE FROM teacher_worlds WHERE world_id = ?")
        .bind(world_id)
        .execute(&mut *tx)
        .await?;
    for account in accounts.iter().filter(|name| is_account(name)) {
        sqlx::query("INSERT OR IGNORE INTO teacher_worlds (world_id, account) VALUES (?, ?)")
            .bind(world_id)
            .bind(account)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(())
}

/// Returns true if an account holds the privilege in this world.
pub async fn holds_in(pool: &SqlitePool, world_id: &str, account: &str) -> Result<bool> {
    let found: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM teacher_worlds WHERE world_id = ? AND account = ?")
            .bind(world_id)
            .bind(account)
            .fetch_optional(pool)
            .await?;
    Ok(found.is_some())
}

/// Returns the ids of the worlds in which an account holds the
/// privilege. Without any, the web access is blocked.
pub async fn worlds_of(pool: &SqlitePool, account: &str) -> Result<Vec<String>> {
    let rows =
        sqlx::query("SELECT world_id FROM teacher_worlds WHERE account = ? ORDER BY world_id")
            .bind(account)
            .fetch_all(pool)
            .await?;
    Ok(rows.iter().map(|row| row.get("world_id")).collect())
}

/// Returns the names of the worlds in which an account holds the
/// privilege, sorted.
pub async fn world_names_of(pool: &SqlitePool, account: &str) -> Result<Vec<String>> {
    let rows = sqlx::query(
        "SELECT worlds.name AS name FROM teacher_worlds
         JOIN worlds ON worlds.id = teacher_worlds.world_id
         WHERE teacher_worlds.account = ? ORDER BY worlds.name",
    )
    .bind(account)
    .fetch_all(pool)
    .await?;
    Ok(rows.iter().map(|row| row.get("name")).collect())
}

/// What a request at the desk led to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Change {
    /// Nothing was done, for example a mail was asked for too soon.
    Nothing,
    /// The stored state changed.
    Changed,
    /// The stored state changed and a confirmation mail has to go out.
    Mail { to: String, token: String },
}

/// Starts a new confirmation for the pending address of an account.
async fn start_confirmation(
    pool: &SqlitePool,
    account: &str,
    email: &str,
    now: i64,
) -> Result<Change> {
    let token = keys::random(TOKEN_PREFIX);
    sqlx::query(
        "INSERT INTO teachers
            (account, pending_email, token_hash, token_expires_at, last_mail_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT (account) DO UPDATE SET
            pending_email = excluded.pending_email, token_hash = excluded.token_hash,
            token_expires_at = excluded.token_expires_at, last_mail_at = excluded.last_mail_at",
    )
    .bind(account)
    .bind(email)
    .bind(keys::hash(&token))
    .bind(now + TOKEN_SECONDS)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await?;
    Ok(Change::Mail {
        to: email.to_owned(),
        token,
    })
}

/// Does what a teacher asked for at the desk. Returns `None` if the
/// request makes no sense. The caller has checked that the account holds
/// the privilege.
pub async fn request(
    pool: &SqlitePool,
    request: &WebAccessRequest,
    now: i64,
) -> Result<Option<Change>> {
    let account = request.account.as_str();
    if !is_account(account) {
        return Ok(None);
    }
    let row =
        sqlx::query("SELECT email, pending_email, last_mail_at FROM teachers WHERE account = ?")
            .bind(account)
            .fetch_optional(pool)
            .await?;
    let confirmed: Option<String> = row.as_ref().and_then(|row| row.get("email"));
    let pending: Option<String> = row.as_ref().and_then(|row| row.get("pending_email"));
    let last_mail: Option<i64> = row.as_ref().and_then(|row| row.get("last_mail_at"));
    let too_soon = last_mail.is_some_and(|at| now - at < MAIL_PAUSE_SECONDS);

    match request.action {
        WebAccessAction::Set => {
            let Some(email) = request.email.as_deref().and_then(normalize_email) else {
                return Ok(None);
            };
            if confirmed.as_deref() == Some(email.as_str()) {
                // Back to the address that is confirmed already.
                sqlx::query(
                    "UPDATE teachers SET pending_email = NULL, token_hash = NULL,
                        token_expires_at = NULL WHERE account = ?",
                )
                .bind(account)
                .execute(pool)
                .await?;
                return Ok(Some(Change::Changed));
            }
            if pending.as_deref() == Some(email.as_str()) && too_soon {
                return Ok(Some(Change::Nothing));
            }
            Ok(Some(start_confirmation(pool, account, &email, now).await?))
        }
        WebAccessAction::Resend => match pending {
            Some(email) if !too_soon => {
                Ok(Some(start_confirmation(pool, account, &email, now).await?))
            }
            _ => Ok(Some(Change::Nothing)),
        },
        WebAccessAction::Remove => {
            let removed = sqlx::query("DELETE FROM teachers WHERE account = ?")
                .bind(account)
                .execute(pool)
                .await?
                .rows_affected();
            Ok(Some(if removed > 0 {
                Change::Changed
            } else {
                Change::Nothing
            }))
        }
    }
}

/// Why an address could not be confirmed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfirmError {
    /// The token is unknown, used or too old.
    InvalidToken,
    /// The address belongs to another account by now.
    AddressTaken,
}

/// Confirms the pending address a token stands for and returns the
/// account. A token works once.
pub async fn confirm(
    pool: &SqlitePool,
    token: &str,
    now: i64,
) -> Result<Result<String, ConfirmError>> {
    let mut tx = pool.begin().await?;
    let row = sqlx::query(
        "SELECT account, pending_email FROM teachers
         WHERE token_hash = ? AND token_expires_at > ? AND pending_email IS NOT NULL",
    )
    .bind(keys::hash(token))
    .bind(now)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(row) = row else {
        return Ok(Err(ConfirmError::InvalidToken));
    };
    let account: String = row.get("account");
    let email: String = row.get("pending_email");

    let taken: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM teachers WHERE email = ? AND account <> ?")
            .bind(&email)
            .bind(&account)
            .fetch_optional(&mut *tx)
            .await?;
    if taken.is_some() {
        return Ok(Err(ConfirmError::AddressTaken));
    }
    sqlx::query(
        "UPDATE teachers SET email = ?, pending_email = NULL, token_hash = NULL,
            token_expires_at = NULL, confirmed_at = ? WHERE account = ?",
    )
    .bind(&email)
    .bind(now)
    .bind(&account)
    .execute(&mut *tx)
    .await?;
    // A login link that is still open went to the old address.
    sqlx::query("DELETE FROM login_tokens WHERE account = ?")
        .bind(&account)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Ok(account))
}

/// Returns how the web access of an account stands, as a world may see
/// it: with shortened addresses.
pub async fn status(pool: &SqlitePool, account: &str) -> Result<WebAccessStatus> {
    let row = sqlx::query("SELECT email, pending_email FROM teachers WHERE account = ?")
        .bind(account)
        .fetch_optional(pool)
        .await?;
    let shortened = |column: &str| {
        row.as_ref()
            .and_then(|row| row.get::<Option<String>, _>(column))
            .map(|email| mask(&email))
    };
    Ok(WebAccessStatus {
        account: account.to_owned(),
        address: shortened("email"),
        pending: shortened("pending_email"),
    })
}

/// A teacher, for people who look after the backend.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Teacher {
    pub account: String,
    pub email: Option<String>,
    pub pending_email: Option<String>,
    /// Number of worlds in which the account holds the privilege.
    pub worlds: i64,
}

/// Lists everybody who holds the privilege somewhere or has entered an
/// address, by account name.
pub async fn list(pool: &SqlitePool) -> Result<Vec<Teacher>> {
    let rows = sqlx::query(
        "SELECT names.account AS account, teachers.email AS email,
                teachers.pending_email AS pending_email,
                (SELECT count(*) FROM teacher_worlds
                 WHERE teacher_worlds.account = names.account) AS worlds
         FROM (SELECT account FROM teachers UNION SELECT account FROM teacher_worlds) AS names
         LEFT JOIN teachers ON teachers.account = names.account
         ORDER BY names.account",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .iter()
        .map(|row| Teacher {
            account: row.get("account"),
            email: row.get("email"),
            pending_email: row.get("pending_email"),
            worlds: row.get("worlds"),
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, worlds};

    fn ask(account: &str, action: WebAccessAction, email: Option<&str>) -> WebAccessRequest {
        WebAccessRequest {
            account: account.to_owned(),
            action,
            email: email.map(str::to_owned),
        }
    }

    async fn set(pool: &SqlitePool, account: &str, email: &str, now: i64) -> String {
        let change = request(pool, &ask(account, WebAccessAction::Set, Some(email)), now)
            .await
            .unwrap()
            .unwrap();
        match change {
            Change::Mail { token, .. } => token,
            other => panic!("expected a mail, got {other:?}"),
        }
    }

    #[test]
    fn knows_what_can_be_an_address() {
        assert_eq!(
            normalize_email("  Anna.Muster@Schule.Example "),
            Some("anna.muster@schule.example".to_owned())
        );
        for bad in [
            "",
            "anna",
            "anna@",
            "@schule.example",
            "anna@schule",
            "anna@schule..example",
            "anna@.example",
            "an na@schule.example",
            "anna@schule.example\nBcc: x@y.example",
            "a@b@schule.example",
        ] {
            assert_eq!(normalize_email(bad), None, "{bad:?}");
        }
        let long = format!("{}@schule.example", "a".repeat(250));
        assert_eq!(normalize_email(&long), None);
    }

    #[test]
    fn shortens_addresses() {
        assert_eq!(mask("anna.muster@schule.example"), "a…@schule.example");
        assert_eq!(mask("ä@schule.example"), "ä…@schule.example");
        assert_eq!(mask("broken"), "…");
    }

    #[test]
    fn knows_what_can_be_an_account() {
        assert!(is_account("lehrer_1"));
        assert!(is_account("Anna-B"));
        assert!(!is_account(""));
        assert!(!is_account("anna b"));
        assert!(!is_account("anna@schule"));
        assert!(!is_account(&"a".repeat(61)));
    }

    #[tokio::test]
    async fn an_address_counts_after_its_confirmation() {
        let pool = db::open_in_memory().await.unwrap();
        let token = set(&pool, "lehrer1", "Anna@Schule.Example", 1000).await;
        assert!(token.starts_with(TOKEN_PREFIX));

        let waiting = status(&pool, "lehrer1").await.unwrap();
        assert_eq!(waiting.address, None);
        assert_eq!(waiting.pending.as_deref(), Some("a…@schule.example"));

        assert_eq!(
            confirm(&pool, &token, 1100).await.unwrap(),
            Ok("lehrer1".to_owned())
        );
        let done = status(&pool, "lehrer1").await.unwrap();
        assert_eq!(done.address.as_deref(), Some("a…@schule.example"));
        assert_eq!(done.pending, None);

        // A token works once.
        assert_eq!(
            confirm(&pool, &token, 1200).await.unwrap(),
            Err(ConfirmError::InvalidToken)
        );
    }

    #[tokio::test]
    async fn a_token_gets_too_old_and_unknown_ones_do_nothing() {
        let pool = db::open_in_memory().await.unwrap();
        let token = set(&pool, "lehrer1", "anna@schule.example", 1000).await;
        assert_eq!(
            confirm(&pool, "lepc_made_up", 1001).await.unwrap(),
            Err(ConfirmError::InvalidToken)
        );
        assert_eq!(
            confirm(&pool, &token, 1000 + TOKEN_SECONDS).await.unwrap(),
            Err(ConfirmError::InvalidToken)
        );
        assert_eq!(
            confirm(&pool, &token, 1000 + TOKEN_SECONDS - 1)
                .await
                .unwrap(),
            Ok("lehrer1".to_owned())
        );
    }

    #[tokio::test]
    async fn the_old_address_counts_until_the_new_one_is_confirmed() {
        let pool = db::open_in_memory().await.unwrap();
        let first = set(&pool, "lehrer1", "alt@schule.example", 1000).await;
        confirm(&pool, &first, 1001).await.unwrap().unwrap();

        let second = set(&pool, "lehrer1", "neu@schule.example", 2000).await;
        let between = status(&pool, "lehrer1").await.unwrap();
        assert_eq!(between.address.as_deref(), Some("a…@schule.example"));
        assert_eq!(between.pending.as_deref(), Some("n…@schule.example"));

        confirm(&pool, &second, 2001).await.unwrap().unwrap();
        let after = status(&pool, "lehrer1").await.unwrap();
        assert_eq!(after.address.as_deref(), Some("n…@schule.example"));
        assert_eq!(after.pending, None);
    }

    #[tokio::test]
    async fn entering_the_confirmed_address_drops_the_pending_one() {
        let pool = db::open_in_memory().await.unwrap();
        let first = set(&pool, "lehrer1", "alt@schule.example", 1000).await;
        confirm(&pool, &first, 1001).await.unwrap().unwrap();
        let second = set(&pool, "lehrer1", "tippfehler@schule.example", 2000).await;

        let change = request(
            &pool,
            &ask("lehrer1", WebAccessAction::Set, Some("alt@schule.example")),
            2001,
        )
        .await
        .unwrap();
        assert_eq!(change, Some(Change::Changed));
        let after = status(&pool, "lehrer1").await.unwrap();
        assert_eq!(after.address.as_deref(), Some("a…@schule.example"));
        assert_eq!(after.pending, None);
        assert_eq!(
            confirm(&pool, &second, 2002).await.unwrap(),
            Err(ConfirmError::InvalidToken)
        );
    }

    #[tokio::test]
    async fn a_new_mail_replaces_the_old_link_and_waits_a_minute() {
        let pool = db::open_in_memory().await.unwrap();
        let first = set(&pool, "lehrer1", "anna@schule.example", 1000).await;
        let resend = ask("lehrer1", WebAccessAction::Resend, None);

        assert_eq!(
            request(&pool, &resend, 1030).await.unwrap(),
            Some(Change::Nothing)
        );
        // The same address again is no way around the pause.
        let again = ask("lehrer1", WebAccessAction::Set, Some("anna@schule.example"));
        assert_eq!(
            request(&pool, &again, 1030).await.unwrap(),
            Some(Change::Nothing)
        );

        let Some(Change::Mail { to, token }) = request(&pool, &resend, 1000 + MAIL_PAUSE_SECONDS)
            .await
            .unwrap()
        else {
            panic!("expected a mail");
        };
        assert_eq!(to, "anna@schule.example");
        assert_ne!(token, first);
        assert_eq!(
            confirm(&pool, &first, 1100).await.unwrap(),
            Err(ConfirmError::InvalidToken)
        );
        assert_eq!(
            confirm(&pool, &token, 1100).await.unwrap(),
            Ok("lehrer1".to_owned())
        );

        // Nothing waits any more: nothing to send.
        assert_eq!(
            request(&pool, &resend, 5000).await.unwrap(),
            Some(Change::Nothing)
        );
    }

    #[tokio::test]
    async fn a_corrected_address_gets_its_mail_at_once() {
        let pool = db::open_in_memory().await.unwrap();
        set(&pool, "lehrer1", "anan@schule.example", 1000).await;
        let token = set(&pool, "lehrer1", "anna@schule.example", 1005).await;
        assert_eq!(
            confirm(&pool, &token, 1010).await.unwrap(),
            Ok("lehrer1".to_owned())
        );
    }

    #[tokio::test]
    async fn an_address_belongs_to_one_account() {
        let pool = db::open_in_memory().await.unwrap();
        let first = set(&pool, "lehrer1", "anna@schule.example", 1000).await;
        let second = set(&pool, "lehrer2", "anna@schule.example", 1000).await;
        confirm(&pool, &first, 1001).await.unwrap().unwrap();
        assert_eq!(
            confirm(&pool, &second, 1002).await.unwrap(),
            Err(ConfirmError::AddressTaken)
        );
        assert_eq!(status(&pool, "lehrer2").await.unwrap().address, None);
    }

    #[tokio::test]
    async fn removing_forgets_the_address() {
        let pool = db::open_in_memory().await.unwrap();
        let token = set(&pool, "lehrer1", "anna@schule.example", 1000).await;
        let remove = ask("lehrer1", WebAccessAction::Remove, None);
        assert_eq!(
            request(&pool, &remove, 1001).await.unwrap(),
            Some(Change::Changed)
        );
        assert_eq!(
            request(&pool, &remove, 1002).await.unwrap(),
            Some(Change::Nothing)
        );
        assert_eq!(
            confirm(&pool, &token, 1003).await.unwrap(),
            Err(ConfirmError::InvalidToken)
        );
        let after = status(&pool, "lehrer1").await.unwrap();
        assert_eq!((after.address, after.pending), (None, None));
        assert!(list(&pool).await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn refuses_requests_that_make_no_sense() {
        let pool = db::open_in_memory().await.unwrap();
        for bad in [
            ask("lehrer1", WebAccessAction::Set, None),
            ask("lehrer1", WebAccessAction::Set, Some("no address")),
            ask("not an account", WebAccessAction::Resend, None),
        ] {
            assert_eq!(request(&pool, &bad, 1000).await.unwrap(), None);
        }
    }

    #[tokio::test]
    async fn the_worlds_say_who_holds_the_privilege() {
        let pool = db::open_in_memory().await.unwrap();
        let (first, _) = worlds::add(&pool, "7b").await.unwrap();
        let (second, _) = worlds::add(&pool, "8a").await.unwrap();
        let names = |list: &[&str]| {
            list.iter()
                .map(|name| (*name).to_owned())
                .collect::<Vec<_>>()
        };

        set_holders(
            &pool,
            &first.id,
            &names(&["lehrer1", "lehrer2", "not valid"]),
        )
        .await
        .unwrap();
        set_holders(&pool, &second.id, &names(&["lehrer1"]))
            .await
            .unwrap();
        assert!(holds_in(&pool, &first.id, "lehrer2").await.unwrap());
        assert!(!holds_in(&pool, &second.id, "lehrer2").await.unwrap());
        assert!(!holds_in(&pool, &first.id, "not valid").await.unwrap());
        assert_eq!(worlds_of(&pool, "lehrer1").await.unwrap().len(), 2);

        // The list of a world replaces its old one.
        set_holders(&pool, &first.id, &names(&["lehrer2"]))
            .await
            .unwrap();
        assert_eq!(
            worlds_of(&pool, "lehrer1").await.unwrap(),
            vec![second.id.clone()]
        );
        set_holders(&pool, &second.id, &[]).await.unwrap();
        assert!(worlds_of(&pool, "lehrer1").await.unwrap().is_empty());

        set(&pool, "lehrer1", "anna@schule.example", 1000).await;
        let listed = list(&pool).await.unwrap();
        assert_eq!(listed.len(), 2);
        assert_eq!(listed[0].account, "lehrer1");
        assert_eq!(listed[0].worlds, 0);
        assert_eq!(
            listed[0].pending_email.as_deref(),
            Some("anna@schule.example")
        );
        assert_eq!(listed[1].account, "lehrer2");
        assert_eq!(listed[1].worlds, 1);
    }
}
