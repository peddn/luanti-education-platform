//! The SQLite database: opening it and bringing its tables up to date.

use std::path::Path;
use std::str::FromStr;

use anyhow::{Context, Result};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions};
use sqlx::SqlitePool;

/// Opens the database file, creates it if it is missing, and applies all
/// migrations that are not in it yet.
pub async fn open(path: &Path) -> Result<SqlitePool> {
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("cannot create the folder {}", parent.display()))?;
    }
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .foreign_keys(true)
        // Readers do not block the writer, and the other way round.
        .journal_mode(SqliteJournalMode::Wal);
    let pool = SqlitePoolOptions::new()
        .connect_with(options)
        .await
        .with_context(|| format!("cannot open the database {}", path.display()))?;
    migrate(&pool).await?;
    Ok(pool)
}

/// Opens a database that lives in memory, for tests. It has a single
/// connection, because every connection to ":memory:" is its own database.
pub async fn open_in_memory() -> Result<SqlitePool> {
    let options = SqliteConnectOptions::from_str("sqlite::memory:")?.foreign_keys(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await?;
    migrate(&pool).await?;
    Ok(pool)
}

/// Applies the migrations from the `migrations` folder. They are built
/// into the program, so a server needs nothing but the binary.
async fn migrate(pool: &SqlitePool) -> Result<()> {
    sqlx::migrate!("./migrations")
        .run(pool)
        .await
        .context("cannot apply the database migrations")
}

/// Returns true if the database answers a query.
pub async fn is_alive(pool: &SqlitePool) -> bool {
    sqlx::query_scalar::<_, i64>("SELECT 1")
        .fetch_one(pool)
        .await
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn applies_the_migrations() {
        let pool = open_in_memory().await.unwrap();
        let value: String = sqlx::query_scalar("SELECT value FROM meta WHERE key = 'application'")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(value, "lep-backend");
        assert!(is_alive(&pool).await);
    }

    #[tokio::test]
    async fn creates_the_file_and_its_folder() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("nested").join("lep.sqlite");
        let pool = open(&path).await.unwrap();
        assert!(path.exists());
        pool.close().await;

        // Opening it again applies nothing twice.
        let pool = open(&path).await.unwrap();
        assert!(is_alive(&pool).await);
    }

    #[tokio::test]
    async fn notices_a_closed_database() {
        let pool = open_in_memory().await.unwrap();
        pool.close().await;
        assert!(!is_alive(&pool).await);
    }
}
