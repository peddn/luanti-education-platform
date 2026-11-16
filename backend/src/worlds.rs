//! Worlds in the database: creating them, finding them by their key and
//! noting what they say about themselves.

use anyhow::{bail, Context, Result};
use lep_protocol::world::WorldStarted;
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

use crate::{clock, keys};

/// A world as the backend knows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct World {
    pub id: String,
    pub name: String,
    pub created_at: i64,
    pub last_seen_at: Option<i64>,
    pub started_at: Option<i64>,
    pub engine: Option<String>,
}

fn from_row(row: &sqlx::sqlite::SqliteRow) -> World {
    World {
        id: row.get("id"),
        name: row.get("name"),
        created_at: row.get("created_at"),
        last_seen_at: row.get("last_seen_at"),
        started_at: row.get("started_at"),
        engine: row.get("engine"),
    }
}

fn check_name(name: &str) -> Result<&str> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 60 {
        bail!("the name of a world needs 1 to 60 characters");
    }
    Ok(name)
}

/// Creates a world and returns it with its key. The key cannot be read
/// again later.
pub async fn add(pool: &SqlitePool, name: &str) -> Result<(World, String)> {
    let name = check_name(name)?;
    if find_by_name(pool, name).await?.is_some() {
        bail!("there is already a world called '{name}'");
    }
    let id = Uuid::new_v4().to_string();
    let key = keys::generate();
    sqlx::query("INSERT INTO worlds (id, name, key_hash, created_at) VALUES (?, ?, ?, ?)")
        .bind(&id)
        .bind(name)
        .bind(keys::hash(&key))
        .bind(clock::now())
        .execute(pool)
        .await
        .context("cannot store the world")?;
    let world = find_by_name(pool, name)
        .await?
        .context("the new world is missing")?;
    Ok((world, key))
}

/// Gives a world a new key and returns it. The old key stops working.
pub async fn rekey(pool: &SqlitePool, name: &str) -> Result<String> {
    let key = keys::generate();
    let changed = sqlx::query("UPDATE worlds SET key_hash = ? WHERE name = ?")
        .bind(keys::hash(&key))
        .bind(name.trim())
        .execute(pool)
        .await?
        .rows_affected();
    if changed == 0 {
        bail!("there is no world called '{}'", name.trim());
    }
    Ok(key)
}

/// Returns all worlds, sorted by name.
pub async fn list(pool: &SqlitePool) -> Result<Vec<World>> {
    let rows = sqlx::query(
        "SELECT id, name, created_at, last_seen_at, started_at, engine
         FROM worlds ORDER BY name",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows.iter().map(from_row).collect())
}

pub async fn find_by_name(pool: &SqlitePool, name: &str) -> Result<Option<World>> {
    let row = sqlx::query(
        "SELECT id, name, created_at, last_seen_at, started_at, engine
         FROM worlds WHERE name = ?",
    )
    .bind(name.trim())
    .fetch_optional(pool)
    .await?;
    Ok(row.as_ref().map(from_row))
}

/// Returns the world that calls with this key, and notes the contact.
pub async fn find_by_key(pool: &SqlitePool, key: &str) -> Result<Option<World>> {
    let row = sqlx::query(
        "UPDATE worlds SET last_seen_at = ? WHERE key_hash = ?
         RETURNING id, name, created_at, last_seen_at, started_at, engine",
    )
    .bind(clock::now())
    .bind(keys::hash(key))
    .fetch_optional(pool)
    .await?;
    Ok(row.as_ref().map(from_row))
}

/// Notes what a world said about itself when it started.
pub async fn note_started(
    pool: &SqlitePool,
    world_id: &str,
    time: i64,
    started: &WorldStarted,
) -> Result<()> {
    sqlx::query("UPDATE worlds SET started_at = ?, engine = ?, mods = ? WHERE id = ?")
        .bind(time)
        .bind(&started.engine)
        .bind(serde_json::to_string(&started.mods)?)
        .bind(world_id)
        .execute(pool)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db;

    #[tokio::test]
    async fn a_new_world_is_found_by_its_key_only() {
        let pool = db::open_in_memory().await.unwrap();
        let (world, key) = add(&pool, " Class 7b ").await.unwrap();
        assert_eq!(world.name, "Class 7b");
        assert_eq!(world.last_seen_at, None);

        let found = find_by_key(&pool, &key).await.unwrap().unwrap();
        assert_eq!(found.id, world.id);
        assert!(found.last_seen_at.is_some());
        assert!(find_by_key(&pool, "lepw_wrong").await.unwrap().is_none());
        assert!(find_by_key(&pool, "").await.unwrap().is_none());

        // The key itself is nowhere in the database.
        let stored: String = sqlx::query_scalar("SELECT key_hash FROM worlds")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_ne!(stored, key);
    }

    #[tokio::test]
    async fn names_are_unique_and_checked() {
        let pool = db::open_in_memory().await.unwrap();
        add(&pool, "7b").await.unwrap();
        assert!(add(&pool, "7b").await.is_err());
        assert!(add(&pool, "   ").await.is_err());
        assert!(add(&pool, &"x".repeat(61)).await.is_err());
        assert_eq!(list(&pool).await.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn a_new_key_replaces_the_old_one() {
        let pool = db::open_in_memory().await.unwrap();
        let (_, old_key) = add(&pool, "7b").await.unwrap();
        let new_key = rekey(&pool, "7b").await.unwrap();
        assert!(find_by_key(&pool, &old_key).await.unwrap().is_none());
        assert!(find_by_key(&pool, &new_key).await.unwrap().is_some());
        assert!(rekey(&pool, "8a").await.is_err());
    }

    #[tokio::test]
    async fn lists_worlds_by_name() {
        let pool = db::open_in_memory().await.unwrap();
        add(&pool, "8a").await.unwrap();
        add(&pool, "7b").await.unwrap();
        let names: Vec<String> = list(&pool)
            .await
            .unwrap()
            .into_iter()
            .map(|world| world.name)
            .collect();
        assert_eq!(names, ["7b", "8a"]);
    }

    #[tokio::test]
    async fn notes_what_a_started_world_says() {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = add(&pool, "7b").await.unwrap();
        let started = WorldStarted {
            engine: "5.18.0".to_owned(),
            mods: vec!["lep_core".to_owned(), "lep_bridge".to_owned()],
        };
        note_started(&pool, &world.id, 1234, &started)
            .await
            .unwrap();
        let found = find_by_name(&pool, "7b").await.unwrap().unwrap();
        assert_eq!(found.started_at, Some(1234));
        assert_eq!(found.engine.as_deref(), Some("5.18.0"));
    }
}
