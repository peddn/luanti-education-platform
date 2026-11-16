//! Events from the worlds: taking each one in exactly once.

use anyhow::Result;
use lep_protocol::world::{Event, EventOutcome, WorldStarted, EVENT_WORLD_STARTED};
use sqlx::SqlitePool;

use crate::{clock, worlds};

/// Takes in one event of a world and says what was done with it.
///
/// An event counts as seen once it was handled. One that arrives again is
/// a duplicate and changes nothing. Events of an unknown kind or with a
/// payload that does not fit are not remembered: the world is told, and it
/// drops them.
pub async fn take_in(pool: &SqlitePool, world_id: &str, event: &Event) -> Result<EventOutcome> {
    if event.id.trim().is_empty() || event.id.len() > 100 {
        return Ok(EventOutcome::Invalid);
    }
    let seen: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM world_events WHERE world_id = ? AND event_id = ?")
            .bind(world_id)
            .bind(&event.id)
            .fetch_optional(pool)
            .await?;
    if seen.is_some() {
        return Ok(EventOutcome::Duplicate);
    }

    match event.kind.as_str() {
        EVENT_WORLD_STARTED => {
            let Ok(started) = serde_json::from_value::<WorldStarted>(event.payload.clone()) else {
                return Ok(EventOutcome::Invalid);
            };
            worlds::note_started(pool, world_id, event.time, &started).await?;
        }
        _ => return Ok(EventOutcome::Unknown),
    }

    sqlx::query("INSERT INTO world_events (world_id, event_id, received_at) VALUES (?, ?, ?)")
        .bind(world_id)
        .bind(&event.id)
        .bind(clock::now())
        .execute(pool)
        .await?;
    Ok(EventOutcome::Accepted)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db;
    use serde_json::json;

    fn started(id: &str) -> Event {
        Event {
            id: id.to_owned(),
            kind: EVENT_WORLD_STARTED.to_owned(),
            time: 1000,
            payload: json!({ "engine": "5.18.0", "mods": ["lep_core"] }),
        }
    }

    async fn setup() -> (SqlitePool, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        (pool, world.id)
    }

    #[tokio::test]
    async fn takes_an_event_in_once() {
        let (pool, world) = setup().await;
        assert_eq!(
            take_in(&pool, &world, &started("e1")).await.unwrap(),
            EventOutcome::Accepted
        );
        assert_eq!(
            take_in(&pool, &world, &started("e1")).await.unwrap(),
            EventOutcome::Duplicate
        );
        assert_eq!(
            take_in(&pool, &world, &started("e2")).await.unwrap(),
            EventOutcome::Accepted
        );

        let found = worlds::find_by_name(&pool, "7b").await.unwrap().unwrap();
        assert_eq!(found.started_at, Some(1000));
        assert_eq!(found.engine.as_deref(), Some("5.18.0"));
    }

    #[tokio::test]
    async fn the_same_id_from_another_world_is_another_event() {
        let (pool, world) = setup().await;
        let (other, _) = worlds::add(&pool, "8a").await.unwrap();
        assert_eq!(
            take_in(&pool, &world, &started("e1")).await.unwrap(),
            EventOutcome::Accepted
        );
        assert_eq!(
            take_in(&pool, &other.id, &started("e1")).await.unwrap(),
            EventOutcome::Accepted
        );
    }

    #[tokio::test]
    async fn does_not_remember_what_it_cannot_use() {
        let (pool, world) = setup().await;
        let mut unknown = started("e1");
        unknown.kind = "from_the_future".to_owned();
        assert_eq!(
            take_in(&pool, &world, &unknown).await.unwrap(),
            EventOutcome::Unknown
        );

        let mut invalid = started("e2");
        invalid.payload = json!({ "engine": 5 });
        assert_eq!(
            take_in(&pool, &world, &invalid).await.unwrap(),
            EventOutcome::Invalid
        );

        let mut no_id = started("");
        no_id.id = " ".to_owned();
        assert_eq!(
            take_in(&pool, &world, &no_id).await.unwrap(),
            EventOutcome::Invalid
        );

        // Nothing of this counts as seen: a later, proper event with the
        // same id is taken in.
        assert_eq!(
            take_in(&pool, &world, &started("e1")).await.unwrap(),
            EventOutcome::Accepted
        );
    }
}
