//! The reward table of a group: what is paid for which occasion.
//!
//! The world keeps the table and checks every change. The backend
//! mirrors what the world reports and passes on what a teacher orders.

use anyhow::Result;
use lep_protocol::web::{ChangeState, GroupRewards};
use lep_protocol::world::{RewardChoice, RewardTable, Rewards, SetRewards, JOB_SET_REWARDS};
use sqlx::{Row, SqlitePool};

use crate::jobs;

/// The most one occasion pays before the effort multiplies it, and the
/// highest daily limit. The world holds the same limits.
pub const MAX_COUNT: u32 = 99;
pub const MAX_DAILY_LIMIT: u32 = 20;

/// Most items a world may offer, and the longest name and title.
const MAX_CHOICES: usize = 100;
const MAX_TEXT: usize = 100;

/// Why a change of the reward table was not ordered.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderError {
    /// The world has not reported a table yet.
    NotReported,
    /// A count or the daily limit is out of range, or an item is not
    /// one of the choices.
    Invalid,
}

fn is_item(name: &str) -> bool {
    let mut parts = name.split(':');
    let fits = |part: Option<&str>| {
        part.is_some_and(|part| {
            !part.is_empty() && part.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        })
    };
    name.len() <= MAX_TEXT && fits(parts.next()) && fits(parts.next()) && parts.next().is_none()
}

fn rows(table: &RewardTable) -> [&lep_protocol::world::RewardRow; 5] {
    [
        &table.task,
        &table.daily,
        &table.level,
        &table.stage,
        &table.module,
    ]
}

/// Stores what a world reported about its rewards. Returns false if the
/// payload makes no sense.
pub async fn store(pool: &SqlitePool, world_id: &str, time: i64, report: &Rewards) -> Result<bool> {
    let sane = rows(&report.table)
        .iter()
        .all(|row| is_item(&row.name) && row.count >= 1)
        && report.choices.len() <= MAX_CHOICES
        && report.choices.iter().all(|choice| {
            is_item(&choice.name) && !choice.title.is_empty() && choice.title.len() <= MAX_TEXT
        });
    if !sane {
        return Ok(false);
    }
    sqlx::query(
        "INSERT OR REPLACE INTO reward_tables (world_id, reward_table, choices, reported_at)
         VALUES (?, ?, ?, ?)",
    )
    .bind(world_id)
    .bind(serde_json::to_string(&report.table)?)
    .bind(serde_json::to_string(&report.choices)?)
    .bind(time)
    .execute(pool)
    .await?;
    Ok(true)
}

async fn mirror(
    pool: &SqlitePool,
    world_id: &str,
) -> Result<Option<(RewardTable, Vec<RewardChoice>)>> {
    let row = sqlx::query("SELECT reward_table, choices FROM reward_tables WHERE world_id = ?")
        .bind(world_id)
        .fetch_optional(pool)
        .await?;
    let Some(row) = row else {
        return Ok(None);
    };
    let Ok(table) = serde_json::from_str(row.get("reward_table")) else {
        // A table from before a row was added: the world reports again.
        return Ok(None);
    };
    Ok(Some((
        table,
        serde_json::from_str(row.get("choices")).unwrap_or_default(),
    )))
}

/// Returns the reward table of a group with the items to choose from
/// and how far a change is that was ordered.
pub async fn of_group(pool: &SqlitePool, world_id: &str) -> Result<GroupRewards> {
    let mirrored = mirror(pool, world_id).await?;
    let newest = sqlx::query(
        "SELECT finished_at, ok FROM jobs WHERE world_id = ? AND kind = ?
         ORDER BY finished_at IS NULL DESC, rowid DESC LIMIT 1",
    )
    .bind(world_id)
    .bind(JOB_SET_REWARDS)
    .fetch_optional(pool)
    .await?;
    let change = newest.and_then(|row| {
        if row.get::<Option<i64>, _>("finished_at").is_none() {
            Some(ChangeState::Pending)
        } else if row.get::<Option<bool>, _>("ok") == Some(false) {
            Some(ChangeState::Refused)
        } else {
            None
        }
    });
    let (table, choices) = match mirrored {
        Some((table, choices)) => (Some(table), choices),
        None => (None, Vec::new()),
    };
    Ok(GroupRewards {
        table,
        choices,
        change,
        max_count: MAX_COUNT,
        max_daily_limit: MAX_DAILY_LIMIT,
    })
}

/// Orders the world of a group to set its reward table, or to put the
/// default back if no table is given. The world checks it again.
/// @param by Account name of the teacher, for the protocol of the world.
pub async fn order(
    pool: &SqlitePool,
    world_id: &str,
    table: Option<RewardTable>,
    by: &str,
) -> Result<Result<(), OrderError>> {
    let Some((_, choices)) = mirror(pool, world_id).await? else {
        return Ok(Err(OrderError::NotReported));
    };
    if let Some(table) = &table {
        let fits = rows(table).iter().all(|row| {
            (1..=MAX_COUNT).contains(&row.count)
                && choices.iter().any(|choice| choice.name == row.name)
        }) && table.daily_limit <= MAX_DAILY_LIMIT;
        if !fits {
            return Ok(Err(OrderError::Invalid));
        }
    }
    let payload = SetRewards {
        table,
        by: by.to_owned(),
    };
    jobs::add(
        pool,
        world_id,
        JOB_SET_REWARDS,
        &serde_json::to_value(payload)?,
    )
    .await?;
    Ok(Ok(()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, worlds};
    use lep_protocol::world::{JobResult, RewardRow};

    fn row(name: &str, count: u32) -> RewardRow {
        RewardRow {
            name: name.to_owned(),
            count,
        }
    }

    fn table() -> RewardTable {
        RewardTable {
            task: row("default:steel_ingot", 1),
            daily: row("default:gold_ingot", 1),
            level: row("default:gold_ingot", 1),
            stage: row("default:diamond", 1),
            module: row("default:diamond", 3),
            daily_limit: 5,
        }
    }

    fn report() -> Rewards {
        Rewards {
            table: table(),
            choices: [
                ("default:steel_ingot", "Stahlbarren"),
                ("default:gold_ingot", "Goldbarren"),
                ("default:diamond", "Diamant"),
                ("default:coal_lump", "Kohlestück"),
            ]
            .into_iter()
            .map(|(name, title)| RewardChoice {
                name: name.to_owned(),
                title: title.to_owned(),
            })
            .collect(),
        }
    }

    async fn setup() -> (SqlitePool, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        (pool, world.id)
    }

    #[tokio::test]
    async fn mirrors_what_the_world_reports() {
        let (pool, world) = setup().await;
        let nothing = of_group(&pool, &world).await.unwrap();
        assert_eq!(nothing.table, None);
        assert!(nothing.choices.is_empty());
        assert_eq!((nothing.max_count, nothing.max_daily_limit), (99, 20));

        assert!(store(&pool, &world, 100, &report()).await.unwrap());
        let shown = of_group(&pool, &world).await.unwrap();
        assert_eq!(shown.table, Some(table()));
        assert_eq!(shown.choices.len(), 4);
        assert_eq!(shown.choices[3].title, "Kohlestück");
        assert_eq!(shown.change, None);

        // A later report replaces the earlier one.
        let mut changed = report();
        changed.table.daily_limit = 9;
        changed.choices.truncate(1);
        assert!(store(&pool, &world, 200, &changed).await.unwrap());
        let shown = of_group(&pool, &world).await.unwrap();
        assert_eq!(shown.table.unwrap().daily_limit, 9);
        assert_eq!(shown.choices.len(), 1);
    }

    #[tokio::test]
    async fn takes_no_nonsense_from_a_world() {
        let (pool, world) = setup().await;
        let mut bad = report();
        bad.table.task.name = "steel".to_owned();
        assert!(!store(&pool, &world, 100, &bad).await.unwrap());
        let mut bad = report();
        bad.table.stage.count = 0;
        assert!(!store(&pool, &world, 100, &bad).await.unwrap());
        let mut bad = report();
        bad.choices[0].title = String::new();
        assert!(!store(&pool, &world, 100, &bad).await.unwrap());
        let mut bad = report();
        bad.choices[0].name = "a:b:c".to_owned();
        assert!(!store(&pool, &world, 100, &bad).await.unwrap());
        assert_eq!(of_group(&pool, &world).await.unwrap().table, None);
    }

    #[tokio::test]
    async fn orders_a_table_only_with_items_that_can_be_chosen() {
        let (pool, world) = setup().await;
        let early = order(&pool, &world, Some(table()), "lehrer1")
            .await
            .unwrap();
        assert_eq!(early, Err(OrderError::NotReported));
        store(&pool, &world, 100, &report()).await.unwrap();

        let changes: [fn(&mut RewardTable); 5] = [
            |table| table.task.name = "default:mese".to_owned(),
            |table| table.daily.count = 0,
            |table| table.level.count = 100,
            |table| table.daily_limit = 21,
            |table| table.module.name = String::new(),
        ];
        for (index, change) in changes.iter().enumerate() {
            let mut wanted = table();
            change(&mut wanted);
            let result = order(&pool, &world, Some(wanted), "lehrer1").await.unwrap();
            assert_eq!(result, Err(OrderError::Invalid), "case {index}");
        }
        assert!(jobs::take_waiting(&pool, &world).await.unwrap().is_empty());

        let mut wanted = table();
        wanted.task = row("default:coal_lump", 4);
        wanted.daily_limit = 0;
        order(&pool, &world, Some(wanted.clone()), "lehrer1")
            .await
            .unwrap()
            .unwrap();
        let waiting = jobs::take_waiting(&pool, &world).await.unwrap();
        assert_eq!(waiting[0].kind, JOB_SET_REWARDS);
        assert_eq!(
            waiting[0].payload,
            serde_json::json!({ "table": wanted, "by": "lehrer1" })
        );
        // The old table counts until the world reports the new one.
        let shown = of_group(&pool, &world).await.unwrap();
        assert_eq!(shown.table, Some(table()));
        assert_eq!(shown.change, Some(ChangeState::Pending));

        let refused = JobResult {
            ok: false,
            message: "task".to_owned(),
        };
        jobs::finish(&pool, &world, &waiting[0].id, &refused)
            .await
            .unwrap();
        assert_eq!(
            of_group(&pool, &world).await.unwrap().change,
            Some(ChangeState::Refused)
        );
    }

    #[tokio::test]
    async fn orders_the_default_back_without_a_table() {
        let (pool, world) = setup().await;
        store(&pool, &world, 100, &report()).await.unwrap();
        order(&pool, &world, None, "leitung")
            .await
            .unwrap()
            .unwrap();
        let waiting = jobs::take_waiting(&pool, &world).await.unwrap();
        assert_eq!(waiting[0].payload, serde_json::json!({ "by": "leitung" }));
        let done = JobResult {
            ok: true,
            message: "set".to_owned(),
        };
        jobs::finish(&pool, &world, &waiting[0].id, &done)
            .await
            .unwrap();
        assert_eq!(of_group(&pool, &world).await.unwrap().change, None);
    }
}
