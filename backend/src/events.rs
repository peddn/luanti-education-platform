//! Events from the worlds: taking each one in exactly once.

use anyhow::Result;
use lep_protocol::web::ChangeTopic;
use lep_protocol::world::{
    AccountRemoved, AccountUsed, AccountsCreated, DisplayName, Event, EventOutcome, Modules,
    Progress, ProtocolEntry, Teachers, Trophies, WebAccessRequest, WorldStarted,
    EVENT_ACCOUNTS_CREATED, EVENT_ACCOUNT_REMOVED, EVENT_ACCOUNT_USED, EVENT_DISPLAY_NAME,
    EVENT_MODULES, EVENT_PROGRESS, EVENT_PROTOCOL, EVENT_TEACHERS, EVENT_TROPHIES,
    EVENT_WEB_ACCESS, EVENT_WORLD_STARTED,
};
use serde::de::DeserializeOwned;

use crate::app::AppState;
use crate::display_names::{self, Stored};
use crate::{clock, removals, state, students, web_access, worlds};

/// Reads the payload of an event as the type its kind asks for.
///
/// A payload whose only content is an empty list arrives as `null`: a Lua
/// table without entries cannot say what it is, and after a night in the
/// queue of a world nothing of it is left. It is read as an object
/// without fields.
fn payload<T: DeserializeOwned>(event: &Event) -> Option<T> {
    if event.payload.is_null() {
        return serde_json::from_value(serde_json::json!({})).ok();
    }
    serde_json::from_value(event.payload.clone()).ok()
}

/// Takes in one event of a world and says what was done with it.
///
/// An event counts as seen once it was handled. One that arrives again is
/// a duplicate and changes nothing. Events of an unknown kind or with a
/// payload that does not fit are not remembered: the world is told, and it
/// drops them.
pub async fn take_in(app: &AppState, world_id: &str, event: &Event) -> Result<EventOutcome> {
    let pool = &app.db;
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

    // Each kind is stored by its own function, which says whether the
    // payload made sense.
    let usable = match event.kind.as_str() {
        EVENT_WORLD_STARTED => match payload::<WorldStarted>(event) {
            Some(started) => {
                worlds::note_started(pool, world_id, event.time, &started).await?;
                true
            }
            None => false,
        },
        EVENT_MODULES => match payload::<Modules>(event) {
            Some(modules) => {
                state::store_modules(pool, world_id, &modules).await?;
                true
            }
            None => false,
        },
        EVENT_PROGRESS => match payload::<Progress>(event) {
            Some(progress) => state::store_progress(pool, world_id, event.time, &progress).await?,
            None => false,
        },
        EVENT_TROPHIES => match payload::<Trophies>(event) {
            Some(trophies) => state::store_trophies(pool, world_id, event.time, &trophies).await?,
            None => false,
        },
        EVENT_PROTOCOL => match payload::<ProtocolEntry>(event) {
            Some(entry) => state::store_protocol_entry(pool, world_id, event.time, &entry).await?,
            None => false,
        },
        EVENT_TEACHERS => match payload::<Teachers>(event) {
            Some(teachers) => {
                web_access::note_holders(app, world_id, &teachers).await?;
                true
            }
            None => false,
        },
        EVENT_ACCOUNTS_CREATED => match payload::<AccountsCreated>(event) {
            Some(report) => {
                students::note_created(pool, world_id, &report).await?;
                crate::staff::note_created(pool, &report).await?;
                true
            }
            None => false,
        },
        EVENT_DISPLAY_NAME => match payload::<DisplayName>(event) {
            Some(reported) => {
                match display_names::store(pool, world_id, event.time, &reported).await? {
                    Stored::Invalid => false,
                    Stored::Kept => true,
                    Stored::NewName => {
                        // Nobody approves names: the teachers hear of each.
                        let name = reported.name.as_deref().unwrap_or_default();
                        display_names::tell_teachers(app, world_id, &reported.account, name)
                            .await?;
                        true
                    }
                }
            }
            None => false,
        },
        EVENT_ACCOUNT_USED => match payload::<AccountUsed>(event) {
            Some(used) => removals::note_used(pool, world_id, &used).await?,
            None => false,
        },
        EVENT_ACCOUNT_REMOVED => match payload::<AccountRemoved>(event) {
            Some(removed) => {
                let done = removals::note_removed(pool, world_id, event.time, &removed).await?;
                if done {
                    tracing::warn!(world = %world_id, account = %removed.account, "an account was deleted on request");
                }
                done
            }
            None => false,
        },
        EVENT_WEB_ACCESS => match payload::<WebAccessRequest>(event) {
            Some(request) => web_access::handle(app, world_id, &request).await?,
            None => false,
        },
        _ => return Ok(EventOutcome::Unknown),
    };
    if !usable {
        return Ok(EventOutcome::Invalid);
    }

    sqlx::query("INSERT INTO world_events (world_id, event_id, received_at) VALUES (?, ?, ?)")
        .bind(world_id)
        .bind(&event.id)
        .bind(clock::now())
        .execute(pool)
        .await?;
    app.changes.tell(world_id, topics_of(&event.kind));
    Ok(EventOutcome::Accepted)
}

/// Returns the parts of a group an event of a kind changes, for the
/// pages that are open in browsers.
fn topics_of(kind: &str) -> &'static [ChangeTopic] {
    match kind {
        EVENT_MODULES | EVENT_PROGRESS | EVENT_TROPHIES => &[ChangeTopic::Progress],
        // A display name stands in the list and next to the progress.
        EVENT_DISPLAY_NAME | EVENT_ACCOUNTS_CREATED => {
            &[ChangeTopic::Students, ChangeTopic::Progress]
        }
        EVENT_ACCOUNT_USED => &[ChangeTopic::Students],
        EVENT_ACCOUNT_REMOVED => &[
            ChangeTopic::Students,
            ChangeTopic::Progress,
            ChangeTopic::Protocols,
        ],
        EVENT_TEACHERS | EVENT_WEB_ACCESS | EVENT_WORLD_STARTED => &[ChangeTopic::Group],
        EVENT_PROTOCOL => &[ChangeTopic::Protocols],
        _ => &[],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db;
    use serde_json::json;
    use sqlx::SqlitePool;

    /// Takes an event in with a state around the pool.
    async fn take_in(pool: &SqlitePool, world_id: &str, event: &Event) -> Result<EventOutcome> {
        super::take_in(&AppState::new(pool.clone()), world_id, event).await
    }

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
    async fn takes_in_state_and_protocol_entries() {
        let (pool, world) = setup().await;
        let event = |id: &str, kind: &str, payload| Event {
            id: id.to_owned(),
            kind: kind.to_owned(),
            time: 1000,
            payload,
        };
        let cases = [
            event(
                "m",
                "modules",
                json!({ "modules": [
                { "id": "lep_math:math", "title": "Kopfrechnen", "levels": [
                    { "stage": false, "tasks": [{ "id": "add_10", "title": "A", "required": 10 }] }
                ] }
            ] }),
            ),
            event(
                "p",
                "progress",
                json!({
                    "account": "anna", "module": "lep_math:math", "level": 2, "locked": false,
                    "percent": 50, "completed": false, "tasks": null
                }),
            ),
            event(
                "t",
                "trophies",
                json!({ "account": "anna", "trophies": null }),
            ),
            event(
                "c",
                "protocol",
                json!({
                    "protocol": "chat", "account": "anna", "fields": { "kind": "chat", "text": "hi" }
                }),
            ),
        ];
        for case in &cases {
            assert_eq!(
                take_in(&pool, &world, case).await.unwrap(),
                EventOutcome::Accepted
            );
            assert_eq!(
                take_in(&pool, &world, case).await.unwrap(),
                EventOutcome::Duplicate
            );
        }
        // A protocol entry that arrived twice is stored once.
        let entries: i64 = sqlx::query_scalar("SELECT count(*) FROM protocol_entries")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(entries, 1);

        let unknown_protocol = event(
            "x",
            "protocol",
            json!({
                "protocol": "diary", "account": "anna", "fields": {}
            }),
        );
        assert_eq!(
            take_in(&pool, &world, &unknown_protocol).await.unwrap(),
            EventOutcome::Invalid
        );
        let no_level = event("y", "progress", json!({ "account": "anna", "module": "m" }));
        assert_eq!(
            take_in(&pool, &world, &no_level).await.unwrap(),
            EventOutcome::Invalid
        );
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
