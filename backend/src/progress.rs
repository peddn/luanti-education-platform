//! Where the students of a group stand, for the browser.
//!
//! The worlds write, the backend mirrors: what is shown here is what a
//! world reported last. A teacher who wants a change orders it from the
//! world, and sees it once the world has reported the new state.

use std::collections::HashMap;

use anyhow::Result;
use lep_protocol::web::{
    ChangeState, EarnedTrophy, GroupProgress, ModuleProgress, ProgressChange, ProgressModule,
    ProgressTask, StudentProgress,
};
use lep_protocol::world::{
    Level, SetLevel, SetLocked, TaskProgress, JOB_SET_LEVEL, JOB_SET_LOCKED,
};
use sqlx::{Row, SqlitePool};

use crate::jobs;

/// A module with the workload of its levels.
struct Known {
    id: String,
    title: String,
    levels: Vec<Level>,
}

async fn modules_of(pool: &SqlitePool, world_id: &str) -> Result<Vec<Known>> {
    let rows = sqlx::query(
        "SELECT module_id, title, levels FROM modules WHERE world_id = ? ORDER BY position",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    Ok(rows
        .iter()
        .map(|row| Known {
            id: row.get("module_id"),
            title: row.get("title"),
            levels: serde_json::from_str(row.get("levels")).unwrap_or_default(),
        })
        .collect())
}

/// The kinds of tasks of a level with what a student has solved of them.
fn tasks_of(module: &Known, level: u32, solved: &[TaskProgress]) -> Vec<ProgressTask> {
    let Some(workload) = module.levels.get(level.saturating_sub(1) as usize) else {
        return Vec::new();
    };
    workload
        .tasks
        .iter()
        .map(|task| ProgressTask {
            title: task.title.clone(),
            solved: solved
                .iter()
                .find(|entry| entry.id == task.id)
                .map_or(0, |entry| entry.solved),
            required: task.required,
        })
        .collect()
}

/// How far the changes a teacher ordered are, by account and module. A
/// change that waits counts before one that was refused.
async fn changes_of(
    pool: &SqlitePool,
    world_id: &str,
) -> Result<HashMap<(String, String), ChangeState>> {
    let rows = sqlx::query(
        "SELECT subject, json_extract(payload, '$.module') AS module, finished_at, ok
         FROM jobs
         WHERE world_id = ? AND kind IN ('set_level', 'set_locked') AND subject IS NOT NULL
         ORDER BY rowid",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    let mut changes = HashMap::new();
    for row in &rows {
        let Some(module) = row.get::<Option<String>, _>("module") else {
            continue;
        };
        let key = (row.get::<String, _>("subject"), module);
        let waits = row.get::<Option<i64>, _>("finished_at").is_none();
        let refused = row.get::<Option<bool>, _>("ok") == Some(false);
        if waits {
            changes.insert(key, ChangeState::Pending);
        } else if changes.get(&key) != Some(&ChangeState::Pending) {
            // The newest answer counts: a change that went through clears
            // an older refusal.
            if refused {
                changes.insert(key, ChangeState::Refused);
            } else {
                changes.remove(&key);
            }
        }
    }
    Ok(changes)
}

/// Returns where the students of a group stand. Listed are the accounts
/// that exist in the world, in the order of the list of students. A
/// student the world has reported nothing about stands at the start.
pub async fn of_group(pool: &SqlitePool, world_id: &str) -> Result<GroupProgress> {
    let modules = modules_of(pool, world_id).await?;
    let accounts: Vec<String> = sqlx::query_scalar(
        "SELECT account FROM students WHERE world_id = ? AND state = 'active' ORDER BY rowid",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;

    let mut reported = HashMap::new();
    let rows = sqlx::query(
        "SELECT account, module_id, level, locked, percent, completed, tasks
         FROM progress WHERE world_id = ?",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    for row in rows {
        reported.insert(
            (
                row.get::<String, _>("account"),
                row.get::<String, _>("module_id"),
            ),
            row,
        );
    }

    let mut trophies: HashMap<String, Vec<EarnedTrophy>> = HashMap::new();
    let rows = sqlx::query(
        "SELECT account, title, material FROM trophies WHERE world_id = ?
         ORDER BY account, trophy_id",
    )
    .bind(world_id)
    .fetch_all(pool)
    .await?;
    for row in &rows {
        trophies
            .entry(row.get("account"))
            .or_default()
            .push(EarnedTrophy {
                title: row.get("title"),
                material: row.get("material"),
            });
    }

    let mut changes = changes_of(pool, world_id).await?;
    let students = accounts
        .into_iter()
        .map(|account| {
            let cells = modules
                .iter()
                .map(|module| {
                    let key = (account.clone(), module.id.clone());
                    let change = changes.remove(&key);
                    match reported.get(&key) {
                        Some(row) => {
                            let level = row.get::<u32, _>("level");
                            let solved: Vec<TaskProgress> =
                                serde_json::from_str(row.get("tasks")).unwrap_or_default();
                            ModuleProgress {
                                module: module.id.clone(),
                                started: true,
                                level,
                                locked: row.get("locked"),
                                percent: row.get("percent"),
                                completed: row.get("completed"),
                                tasks: tasks_of(module, level, &solved),
                                change,
                            }
                        }
                        None => ModuleProgress {
                            module: module.id.clone(),
                            started: false,
                            level: 1,
                            locked: false,
                            percent: 0,
                            completed: false,
                            tasks: tasks_of(module, 1, &[]),
                            change,
                        },
                    }
                })
                .collect();
            StudentProgress {
                trophies: trophies.remove(&account).unwrap_or_default(),
                modules: cells,
                account,
            }
        })
        .collect();

    Ok(GroupProgress {
        modules: modules
            .iter()
            .map(|module| ProgressModule {
                id: module.id.clone(),
                title: module.title.clone(),
                levels: module.levels.len() as u32,
            })
            .collect(),
        students,
    })
}

/// Why a change cannot be ordered.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChangeError {
    /// The group has no such account that exists in the world.
    NoStudent,
    /// The world of the group has no such module.
    NoModule,
    /// The module has no such level.
    BadLevel,
    /// The request changes nothing.
    Empty,
}

/// Orders a change from the world of a group: a level, the lock, or
/// both. Nothing changes here; the world reports the new state.
/// @param by Account name of the teacher, for the protocol of the world.
pub async fn change(
    pool: &SqlitePool,
    world_id: &str,
    account: &str,
    module_id: &str,
    wanted: &ProgressChange,
    by: &str,
) -> Result<Result<(), ChangeError>> {
    if wanted.level.is_none() && wanted.locked.is_none() {
        return Ok(Err(ChangeError::Empty));
    }
    // The name as it is stored: the engine tells letter cases apart.
    let stored: Option<String> = sqlx::query_scalar(
        "SELECT account FROM students WHERE account = ? AND world_id = ? AND state = 'active'",
    )
    .bind(account)
    .bind(world_id)
    .fetch_optional(pool)
    .await?;
    let Some(account) = stored else {
        return Ok(Err(ChangeError::NoStudent));
    };
    let modules = modules_of(pool, world_id).await?;
    let Some(module) = modules.iter().find(|module| module.id == module_id) else {
        return Ok(Err(ChangeError::NoModule));
    };
    if let Some(level) = wanted.level {
        if level < 1 || level as usize > module.levels.len() {
            return Ok(Err(ChangeError::BadLevel));
        }
        let payload = SetLevel {
            account: account.clone(),
            module: module.id.clone(),
            level,
            by: by.to_owned(),
        };
        jobs::add_about(
            pool,
            world_id,
            JOB_SET_LEVEL,
            &serde_json::to_value(payload)?,
            Some(&account),
        )
        .await?;
    }
    if let Some(locked) = wanted.locked {
        let payload = SetLocked {
            account: account.clone(),
            module: module.id.clone(),
            locked,
            by: by.to_owned(),
        };
        jobs::add_about(
            pool,
            world_id,
            JOB_SET_LOCKED,
            &serde_json::to_value(payload)?,
            Some(&account),
        )
        .await?;
    }
    Ok(Ok(()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, state, worlds};
    use lep_protocol::world::{JobResult, Module, Modules, Progress, TaskType, Trophies, Trophy};

    const MATH: &str = "lep_math:math";

    async fn setup() -> (SqlitePool, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        let level = |task: &str, title: &str| Level {
            stage: false,
            tasks: vec![TaskType {
                id: task.to_owned(),
                title: title.to_owned(),
                required: 5,
            }],
        };
        let modules = Modules {
            modules: vec![Module {
                id: MATH.to_owned(),
                title: "Kopfrechnen".to_owned(),
                levels: vec![level("add", "Addieren"), level("sub", "Subtrahieren")],
            }],
        };
        state::store_modules(&pool, &world.id, &modules)
            .await
            .unwrap();
        for (name, state) in [
            ("klugeEule", "active"),
            ("frohesReh", "active"),
            ("stillerBach", "draft"),
        ] {
            sqlx::query(
                "INSERT INTO students (account, world_id, state, created_at) VALUES (?, ?, ?, 0)",
            )
            .bind(name)
            .bind(&world.id)
            .bind(state)
            .execute(&pool)
            .await
            .unwrap();
        }
        (pool, world.id)
    }

    async fn report(pool: &SqlitePool, world: &str, account: &str, level: u32, solved: u32) {
        let progress = Progress {
            account: account.to_owned(),
            module: MATH.to_owned(),
            level,
            locked: level == 2,
            percent: solved * 20,
            completed: false,
            tasks: vec![TaskProgress {
                id: if level == 1 { "add" } else { "sub" }.to_owned(),
                solved,
                required: 5,
            }],
        };
        assert!(state::store_progress(pool, world, 100, &progress)
            .await
            .unwrap());
    }

    fn wanted(level: Option<u32>, locked: Option<bool>) -> ProgressChange {
        ProgressChange { level, locked }
    }

    async fn answer(pool: &SqlitePool, world: &str, ok: bool) {
        for job in jobs::take_waiting(pool, world).await.unwrap() {
            let result = JobResult {
                ok,
                message: String::new(),
            };
            jobs::finish(pool, world, &job.id, &result).await.unwrap();
        }
    }

    #[tokio::test]
    async fn lists_the_students_that_exist_with_what_the_world_reported() {
        let (pool, world) = setup().await;
        report(&pool, &world, "frohesReh", 2, 3).await;
        let trophies = Trophies {
            account: "frohesReh".to_owned(),
            trophies: vec![Trophy {
                id: "t1".to_owned(),
                title: "Rechenpokal".to_owned(),
                material: "gold".to_owned(),
            }],
        };
        state::store_trophies(&pool, &world, 100, &trophies)
            .await
            .unwrap();

        let progress = of_group(&pool, &world).await.unwrap();
        assert_eq!(
            progress.modules,
            [ProgressModule {
                id: MATH.to_owned(),
                title: "Kopfrechnen".to_owned(),
                levels: 2
            }]
        );
        // In the order of the list, without the name that was only rolled.
        let names: Vec<&str> = progress
            .students
            .iter()
            .map(|student| student.account.as_str())
            .collect();
        assert_eq!(names, ["klugeEule", "frohesReh"]);

        // Nothing reported: the start of level 1, with its tasks.
        let fresh = &progress.students[0].modules[0];
        assert!(!fresh.started);
        assert_eq!((fresh.level, fresh.percent, fresh.locked), (1, 0, false));
        assert_eq!(
            fresh.tasks,
            [ProgressTask {
                title: "Addieren".to_owned(),
                solved: 0,
                required: 5
            }]
        );
        assert!(progress.students[0].trophies.is_empty());

        let reported = &progress.students[1].modules[0];
        assert!(reported.started);
        assert_eq!(
            (reported.level, reported.percent, reported.locked),
            (2, 60, true)
        );
        assert_eq!(reported.tasks[0].title, "Subtrahieren");
        assert_eq!(reported.tasks[0].solved, 3);
        assert_eq!(progress.students[1].trophies[0].title, "Rechenpokal");
    }

    #[tokio::test]
    async fn orders_changes_from_the_world_and_shows_how_far_they_are() {
        let (pool, world) = setup().await;
        let cell = |progress: &GroupProgress| progress.students[0].modules[0].clone();

        let both = wanted(Some(2), Some(true));
        assert_eq!(
            change(&pool, &world, "KLUGEEULE", MATH, &both, "lehrer1")
                .await
                .unwrap(),
            Ok(())
        );
        // Nothing has changed here, the change waits.
        let waiting = cell(&of_group(&pool, &world).await.unwrap());
        assert_eq!(
            (waiting.level, waiting.change),
            (1, Some(ChangeState::Pending))
        );
        let other = of_group(&pool, &world).await.unwrap().students[1].modules[0].clone();
        assert_eq!(other.change, None);

        let sent = jobs::take_waiting(&pool, &world).await.unwrap();
        assert_eq!(sent.len(), 2);
        assert_eq!(sent[0].kind, JOB_SET_LEVEL);
        let level: SetLevel = serde_json::from_value(sent[0].payload.clone()).unwrap();
        assert_eq!(
            (
                level.account.as_str(),
                level.module.as_str(),
                level.level,
                level.by.as_str()
            ),
            ("klugeEule", MATH, 2, "lehrer1")
        );
        assert_eq!(sent[1].kind, JOB_SET_LOCKED);
        let locked: SetLocked = serde_json::from_value(sent[1].payload.clone()).unwrap();
        assert!(locked.locked);

        // The world refuses: the list says so, until a change goes through.
        answer(&pool, &world, false).await;
        assert_eq!(
            cell(&of_group(&pool, &world).await.unwrap()).change,
            Some(ChangeState::Refused)
        );
        change(
            &pool,
            &world,
            "klugeEule",
            MATH,
            &wanted(Some(2), None),
            "lehrer1",
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(
            cell(&of_group(&pool, &world).await.unwrap()).change,
            Some(ChangeState::Pending)
        );
        answer(&pool, &world, true).await;
        report(&pool, &world, "klugeEule", 2, 0).await;
        let done = cell(&of_group(&pool, &world).await.unwrap());
        assert_eq!((done.level, done.change), (2, None));
    }

    #[tokio::test]
    async fn refuses_changes_that_cannot_be_made() {
        let (pool, world) = setup().await;
        let (other, _) = worlds::add(&pool, "8a").await.unwrap();
        let level = wanted(Some(1), None);
        let cases = [
            ("niemand", MATH, level.clone(), ChangeError::NoStudent),
            // Only rolled, not in the world yet.
            ("stillerBach", MATH, level.clone(), ChangeError::NoStudent),
            (
                "klugeEule",
                "lep_tz:tz",
                level.clone(),
                ChangeError::NoModule,
            ),
            (
                "klugeEule",
                MATH,
                wanted(Some(0), None),
                ChangeError::BadLevel,
            ),
            (
                "klugeEule",
                MATH,
                wanted(Some(3), None),
                ChangeError::BadLevel,
            ),
            ("klugeEule", MATH, wanted(None, None), ChangeError::Empty),
        ];
        for (account, module, wanted, error) in cases {
            assert_eq!(
                change(&pool, &world, account, module, &wanted, "lehrer1")
                    .await
                    .unwrap(),
                Err(error),
                "{account} {module}"
            );
        }
        // Not through another group.
        assert_eq!(
            change(&pool, &other.id, "klugeEule", MATH, &level, "lehrer1")
                .await
                .unwrap(),
            Err(ChangeError::NoStudent)
        );
        assert!(jobs::take_waiting(&pool, &world).await.unwrap().is_empty());
    }
}
