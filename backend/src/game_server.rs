//! The game server in the database: the key of its agent and what the
//! agent last said. There is exactly one game server for all worlds.

use anyhow::{Context, Result};
use lep_protocol::agent::{AgentReport, SILENT_AFTER_SECONDS};
use lep_protocol::web::GameServer;
use sqlx::{Row, SqlitePool};

use crate::{clock, keys};

/// Gives the agent a key and returns it. A key that existed before stops
/// working; what the agent said so far stays.
pub async fn rekey(pool: &SqlitePool) -> Result<String> {
    let key = keys::generate_for_agent();
    sqlx::query(
        "INSERT INTO game_server (id, key_hash, created_at) VALUES (1, ?, ?)
         ON CONFLICT (id) DO UPDATE SET key_hash = excluded.key_hash",
    )
    .bind(keys::hash(&key))
    .bind(clock::now())
    .execute(pool)
    .await
    .context("cannot store the key of the agent")?;
    Ok(key)
}

/// Returns true if this is the key of the agent.
pub async fn is_key(pool: &SqlitePool, key: &str) -> Result<bool> {
    let found = sqlx::query("SELECT 1 FROM game_server WHERE key_hash = ?")
        .bind(keys::hash(key))
        .fetch_optional(pool)
        .await?;
    Ok(found.is_some())
}

/// Notes what the agent said about the game server.
pub async fn note_report(pool: &SqlitePool, report: &AgentReport) -> Result<()> {
    // The database counts in signed numbers. No disk is that large.
    let free = i64::try_from(report.free_disk_bytes).unwrap_or(i64::MAX);
    sqlx::query(
        "UPDATE game_server
         SET last_seen_at = ?, version = ?, free_disk_bytes = ?, template_version = ?, host = ?
         WHERE id = 1",
    )
    .bind(clock::now())
    .bind(&report.version)
    .bind(free)
    .bind(&report.template)
    .bind(&report.host)
    .execute(pool)
    .await?;
    Ok(())
}

/// Returns the name under which players reach the game server, if the
/// agent reported one.
pub async fn host(pool: &SqlitePool) -> Result<Option<String>> {
    let host: Option<Option<String>> =
        sqlx::query_scalar("SELECT host FROM game_server WHERE id = 1")
            .fetch_optional(pool)
            .await?;
    Ok(host.flatten())
}

/// Describes the game server for the web application. `None` as long as
/// no agent has a key.
pub async fn describe(pool: &SqlitePool) -> Result<Option<GameServer>> {
    describe_at(pool, clock::now()).await
}

async fn describe_at(pool: &SqlitePool, now: i64) -> Result<Option<GameServer>> {
    let row = sqlx::query(
        "SELECT last_seen_at, version, free_disk_bytes, template_version
         FROM game_server WHERE id = 1",
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|row| {
        let last_seen_at: Option<i64> = row.get("last_seen_at");
        let free: Option<i64> = row.get("free_disk_bytes");
        GameServer {
            connected: last_seen_at.is_some_and(|seen| now - seen <= SILENT_AFTER_SECONDS as i64),
            last_seen_at,
            version: row.get("version"),
            free_disk_bytes: free.map(|bytes| bytes.max(0) as u64),
            template: row.get("template_version"),
        }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db;

    fn report() -> AgentReport {
        AgentReport {
            version: "0.1.0".to_owned(),
            free_disk_bytes: 5_000_000_000,
            template: Some("bdbbf00c8a29".to_owned()),
            worlds: Vec::new(),
            host: Some("spiel.schule.example".to_owned()),
        }
    }

    #[tokio::test]
    async fn there_is_no_game_server_without_a_key() {
        let pool = db::open_in_memory().await.unwrap();
        assert_eq!(describe(&pool).await.unwrap(), None);
        assert!(!is_key(&pool, "lepa_anything").await.unwrap());
        // A report without a key changes nothing.
        note_report(&pool, &report()).await.unwrap();
        assert_eq!(describe(&pool).await.unwrap(), None);
    }

    #[tokio::test]
    async fn a_new_key_replaces_the_old_one() {
        let pool = db::open_in_memory().await.unwrap();
        let first = rekey(&pool).await.unwrap();
        assert!(first.starts_with("lepa_"));
        assert!(is_key(&pool, &first).await.unwrap());

        note_report(&pool, &report()).await.unwrap();
        let second = rekey(&pool).await.unwrap();
        assert!(!is_key(&pool, &first).await.unwrap());
        assert!(is_key(&pool, &second).await.unwrap());
        // What the agent said stays.
        let server = describe(&pool).await.unwrap().unwrap();
        assert_eq!(server.version.as_deref(), Some("0.1.0"));
    }

    #[tokio::test]
    async fn the_key_is_not_in_the_database() {
        let pool = db::open_in_memory().await.unwrap();
        let key = rekey(&pool).await.unwrap();
        let stored: String = sqlx::query("SELECT key_hash FROM game_server")
            .fetch_one(&pool)
            .await
            .unwrap()
            .get(0);
        assert_ne!(stored, key);
        assert!(!stored.contains(&key));
    }

    #[tokio::test]
    async fn a_game_server_is_connected_for_a_short_while_after_a_report() {
        let pool = db::open_in_memory().await.unwrap();
        rekey(&pool).await.unwrap();
        let never = describe(&pool).await.unwrap().unwrap();
        assert!(!never.connected);
        assert_eq!(never.last_seen_at, None);
        assert_eq!(never.free_disk_bytes, None);

        note_report(&pool, &report()).await.unwrap();
        let now = clock::now();
        let fresh = describe_at(&pool, now).await.unwrap().unwrap();
        assert!(fresh.connected);
        assert_eq!(fresh.free_disk_bytes, Some(5_000_000_000));
        assert_eq!(fresh.template.as_deref(), Some("bdbbf00c8a29"));
        assert_eq!(
            host(&pool).await.unwrap().as_deref(),
            Some("spiel.schule.example")
        );

        // An agent without a template says so, and the old one is gone.
        let bare = AgentReport {
            template: None,
            ..report()
        };
        note_report(&pool, &bare).await.unwrap();
        assert_eq!(describe(&pool).await.unwrap().unwrap().template, None);

        let later = describe_at(&pool, now + SILENT_AFTER_SECONDS as i64 + 5)
            .await
            .unwrap()
            .unwrap();
        assert!(!later.connected);
        assert!(later.last_seen_at.is_some());
    }
}
