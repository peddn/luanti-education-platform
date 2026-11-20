//! Groups: the worlds as teachers see them.
//!
//! A group is a world, one to one. The school administration sees every
//! group, renames groups and assigns teachers. Every other teacher sees
//! the groups they are assigned to. All of this is checked here, with
//! every request, not in the frontend.

use anyhow::Result;
use lep_protocol::agent::{
    CreateWorld, WorldJob, JOB_CREATE_WORLD, JOB_RESTART_WORLD, JOB_START_WORLD, JOB_STOP_WORLD,
};
use lep_protocol::web::{Group, GroupChange, WorldSetup, WorldStep};
use sqlx::{Row, SqlitePool};

use crate::{game_server, jobs, teachers, worlds};

/// Longest name of a group.
const MAX_NAME: usize = 60;

/// Replaces the list of accounts that hold the privilege of the school
/// administration in a world. Names that cannot be accounts are left out.
pub async fn set_school_admins(
    pool: &SqlitePool,
    world_id: &str,
    accounts: &[String],
) -> Result<()> {
    let mut tx = pool.begin().await?;
    sqlx::query("DELETE FROM school_admin_worlds WHERE world_id = ?")
        .bind(world_id)
        .execute(&mut *tx)
        .await?;
    // The account of a student never counts as school administration.
    let accounts = crate::staff::without_students(&mut tx, accounts).await?;
    for account in accounts.iter().filter(|name| teachers::is_account(name)) {
        sqlx::query("INSERT OR IGNORE INTO school_admin_worlds (world_id, account) VALUES (?, ?)")
            .bind(world_id)
            .bind(account)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(())
}

/// Returns true if an account holds the privilege of the school
/// administration in at least one world.
pub async fn is_school_admin(pool: &SqlitePool, account: &str) -> Result<bool> {
    let found: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM school_admin_worlds WHERE account = ? LIMIT 1")
            .bind(account)
            .fetch_optional(pool)
            .await?;
    Ok(found.is_some())
}

async fn teachers_of(pool: &SqlitePool, world_id: &str) -> Result<Vec<String>> {
    let rows =
        sqlx::query("SELECT account FROM group_teachers WHERE world_id = ? ORDER BY account")
            .bind(world_id)
            .fetch_all(pool)
            .await?;
    Ok(rows.iter().map(|row| row.get("account")).collect())
}

/// Lists the groups an account may see, by name: all of them for the
/// school administration, else the ones the account is assigned to.
pub async fn visible_to(pool: &SqlitePool, account: &str) -> Result<Vec<Group>> {
    let everything = is_school_admin(pool, account).await?;
    let rows = sqlx::query(
        "SELECT id, name, last_seen_at, address, port, running FROM worlds
         WHERE ? OR EXISTS (SELECT 1 FROM group_teachers
                            WHERE group_teachers.world_id = worlds.id
                              AND group_teachers.account = ?)
         ORDER BY name COLLATE NOCASE, name",
    )
    .bind(everything)
    .bind(account)
    .fetch_all(pool)
    .await?;
    // With the name of the game server the agent fixes the address of
    // every world it runs.
    let host = game_server::host(pool).await?;
    let mut groups = Vec::with_capacity(rows.len());
    for row in rows {
        let id: String = row.get("id");
        let port = row
            .get::<Option<i64>, _>("port")
            .and_then(|port| u16::try_from(port).ok());
        let running: Option<bool> = row.get("running");
        let (world, refusal) = setup_of(pool, &id, port, running).await?;
        let (steering, step_refusal) = steering_of(pool, &id).await?;
        groups.push(Group {
            address_fixed: port.is_some() && host.is_some(),
            steering,
            step_refusal,
            teachers: teachers_of(pool, &id).await?,
            id,
            name: row.get("name"),
            last_seen_at: row.get("last_seen_at"),
            address: row.get("address"),
            world,
            refusal,
            port,
        });
    }
    Ok(groups)
}

/// Works out how it stands with the world of a group: from what the
/// agent reported, and before that from how the job to create it went.
async fn setup_of(
    pool: &SqlitePool,
    world_id: &str,
    port: Option<u16>,
    running: Option<bool>,
) -> Result<(WorldSetup, Option<String>)> {
    if port.is_some() {
        let setup = if running == Some(true) {
            WorldSetup::Running
        } else {
            WorldSetup::Stopped
        };
        return Ok((setup, None));
    }
    Ok(
        match jobs::last_for_agent(pool, world_id, JOB_CREATE_WORLD).await? {
            None => (WorldSetup::Manual, None),
            Some(job) if job.finished && job.ok == Some(false) => {
                (WorldSetup::Refused, Some(job.message.unwrap_or_default()))
            }
            // Waiting for the agent, or done and not reported yet.
            Some(_) => (WorldSetup::Pending, None),
        },
    )
}

fn kind_of(step: WorldStep) -> &'static str {
    match step {
        WorldStep::Start => JOB_START_WORLD,
        WorldStep::Stop => JOB_STOP_WORLD,
        WorldStep::Restart => JOB_RESTART_WORLD,
    }
}

/// Looks at the newest job that starts or stops a world: what the agent
/// has not answered yet, or why it refused.
async fn steering_of(
    pool: &SqlitePool,
    world_id: &str,
) -> Result<(Option<WorldStep>, Option<String>)> {
    let row = sqlx::query(
        "SELECT kind, finished_at, ok, message FROM jobs
         WHERE recipient = 'agent' AND world_id = ?
           AND kind IN ('start_world', 'stop_world', 'restart_world')
         ORDER BY created_at DESC, rowid DESC LIMIT 1",
    )
    .bind(world_id)
    .fetch_optional(pool)
    .await?;
    let Some(row) = row else {
        return Ok((None, None));
    };
    let finished = row.get::<Option<i64>, _>("finished_at").is_some();
    if !finished {
        let kind: String = row.get("kind");
        let step = [WorldStep::Start, WorldStep::Stop, WorldStep::Restart]
            .into_iter()
            .find(|step| kind_of(*step) == kind);
        return Ok((step, None));
    }
    if row.get::<Option<bool>, _>("ok") == Some(false) {
        let message: Option<String> = row.get("message");
        return Ok((None, Some(message.unwrap_or_default())));
    }
    Ok((None, None))
}

/// Why the world of a group could not be started or stopped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SteerError {
    /// There is no such group.
    NotFound,
    /// The agent does not run this world: it was set up by hand, or it
    /// does not exist yet.
    NotRun,
}

/// Asks the agent to start or stop the world of a group. The caller has
/// checked that the one who asks may: a teacher of the group or the
/// school administration.
pub async fn steer(pool: &SqlitePool, id: &str, step: WorldStep) -> Result<Result<(), SteerError>> {
    let port: Option<Option<i64>> = sqlx::query_scalar("SELECT port FROM worlds WHERE id = ?")
        .bind(id)
        .fetch_optional(pool)
        .await?;
    match port {
        None => return Ok(Err(SteerError::NotFound)),
        Some(None) => return Ok(Err(SteerError::NotRun)),
        Some(Some(_)) => {}
    }
    let payload = serde_json::to_value(WorldJob {
        world: id.to_owned(),
    })?;
    jobs::add_for_agent(pool, id, kind_of(step), &payload).await?;
    Ok(Ok(()))
}

/// Why a group could not be created.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CreateError {
    /// The name is empty or too long.
    InvalidName,
    /// Another group has this name.
    NameTaken,
    /// There is no agent that could set the world up.
    NoGameServer,
}

/// Creates a group and asks the agent to set its world up and start it.
/// Returns the identifier of the group. The key of the world travels in
/// the job and is shown to nobody.
pub async fn create(pool: &SqlitePool, name: &str) -> Result<Result<String, CreateError>> {
    let Some(name) = check_name(name) else {
        return Ok(Err(CreateError::InvalidName));
    };
    if game_server::describe(pool).await?.is_none() {
        return Ok(Err(CreateError::NoGameServer));
    }
    let taken: Option<i64> =
        sqlx::query_scalar("SELECT 1 FROM worlds WHERE name = ? COLLATE NOCASE")
            .bind(name)
            .fetch_optional(pool)
            .await?;
    if taken.is_some() {
        return Ok(Err(CreateError::NameTaken));
    }
    let (world, key) = worlds::add(pool, name).await?;
    order_setup(pool, &world.id, key).await?;
    Ok(Ok(world.id))
}

async fn order_setup(pool: &SqlitePool, world_id: &str, bridge_key: String) -> Result<()> {
    let payload = serde_json::to_value(CreateWorld {
        world: world_id.to_owned(),
        bridge_key,
    })?;
    jobs::add_for_agent(pool, world_id, JOB_CREATE_WORLD, &payload).await?;
    Ok(())
}

/// Why a refused group could not be tried again or discarded.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RefusedError {
    /// There is no such group.
    NotFound,
    /// The group is not one the agent refused: its world waits, exists,
    /// or was set up by hand.
    NotRefused,
}

/// Returns the name of a group the agent refused, or why it is none.
async fn refused(pool: &SqlitePool, id: &str) -> Result<Result<String, RefusedError>> {
    let row = sqlx::query("SELECT name, port, running FROM worlds WHERE id = ?")
        .bind(id)
        .fetch_optional(pool)
        .await?;
    let Some(row) = row else {
        return Ok(Err(RefusedError::NotFound));
    };
    let port = row
        .get::<Option<i64>, _>("port")
        .and_then(|port| u16::try_from(port).ok());
    let (setup, _) = setup_of(pool, id, port, row.get("running")).await?;
    if setup != WorldSetup::Refused {
        return Ok(Err(RefusedError::NotRefused));
    }
    Ok(Ok(row.get("name")))
}

/// Asks the agent again to set up the world of a group it refused. The
/// world gets a new key: the old one was forgotten with the old job.
pub async fn retry(pool: &SqlitePool, id: &str) -> Result<Result<(), RefusedError>> {
    let name = match refused(pool, id).await? {
        Ok(name) => name,
        Err(why) => return Ok(Err(why)),
    };
    let key = worlds::rekey(pool, &name).await?;
    order_setup(pool, id, key).await?;
    Ok(Ok(()))
}

/// Removes a group the agent refused. Its world never existed, so there
/// is no map, no account and no protocol to lose. Returns its name.
pub async fn discard(pool: &SqlitePool, id: &str) -> Result<Result<String, RefusedError>> {
    let name = match refused(pool, id).await? {
        Ok(name) => name,
        Err(why) => return Ok(Err(why)),
    };
    sqlx::query("DELETE FROM worlds WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(Ok(name))
}

/// Returns one group, if the account may see it.
pub async fn find_visible(pool: &SqlitePool, account: &str, id: &str) -> Result<Option<Group>> {
    Ok(visible_to(pool, account)
        .await?
        .into_iter()
        .find(|group| group.id == id))
}

/// Lists the accounts that can be assigned to groups: everybody who
/// holds the privilege for web access in some world.
pub async fn assignable(pool: &SqlitePool) -> Result<Vec<String>> {
    let rows = sqlx::query("SELECT DISTINCT account FROM teacher_worlds ORDER BY account")
        .fetch_all(pool)
        .await?;
    Ok(rows.iter().map(|row| row.get("account")).collect())
}

/// Why a group could not be changed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChangeError {
    /// There is no such group.
    NotFound,
    /// The name is empty or too long.
    InvalidName,
    /// Another group has this name.
    NameTaken,
    /// This account is not a teacher and cannot be assigned.
    UnknownTeacher(String),
    /// The address is too long or holds characters that do not belong
    /// on a printed slip.
    InvalidAddress,
}

/// Longest address of a world.
const MAX_ADDRESS: usize = 100;

/// Returns a name as it is stored, or `None` if it cannot be one.
pub fn check_name(name: &str) -> Option<&str> {
    let name = name.trim();
    let fits =
        !name.is_empty() && name.chars().count() <= MAX_NAME && !name.chars().any(char::is_control);
    fits.then_some(name)
}

/// Changes the name of a group, its teachers or both. The caller has
/// checked that the school administration asks. Either everything is
/// changed or nothing.
pub async fn change(
    pool: &SqlitePool,
    id: &str,
    change: &GroupChange,
) -> Result<Result<(), ChangeError>> {
    let mut tx = pool.begin().await?;
    let known: Option<i64> = sqlx::query_scalar("SELECT 1 FROM worlds WHERE id = ?")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?;
    if known.is_none() {
        return Ok(Err(ChangeError::NotFound));
    }

    if let Some(name) = &change.name {
        let Some(name) = check_name(name) else {
            return Ok(Err(ChangeError::InvalidName));
        };
        // The same name in other letter case counts as taken: two groups
        // that differ only there would be mixed up.
        let taken: Option<i64> =
            sqlx::query_scalar("SELECT 1 FROM worlds WHERE name = ? COLLATE NOCASE AND id <> ?")
                .bind(name)
                .bind(id)
                .fetch_optional(&mut *tx)
                .await?;
        if taken.is_some() {
            return Ok(Err(ChangeError::NameTaken));
        }
        sqlx::query("UPDATE worlds SET name = ? WHERE id = ?")
            .bind(name)
            .bind(id)
            .execute(&mut *tx)
            .await?;
    }

    if let Some(address) = &change.address {
        // An address that comes from the agent is not entered by hand.
        let fixed: Option<i64> = sqlx::query_scalar(
            "SELECT 1 FROM worlds, game_server
             WHERE worlds.id = ? AND worlds.port IS NOT NULL
               AND game_server.id = 1 AND game_server.host IS NOT NULL",
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?;
        if fixed.is_some() {
            return Ok(Err(ChangeError::InvalidAddress));
        }
        let address = address.trim();
        if address.chars().count() > MAX_ADDRESS || address.chars().any(char::is_control) {
            return Ok(Err(ChangeError::InvalidAddress));
        }
        // An empty text removes the address.
        sqlx::query("UPDATE worlds SET address = ? WHERE id = ?")
            .bind((!address.is_empty()).then_some(address))
            .bind(id)
            .execute(&mut *tx)
            .await?;
    }

    if let Some(accounts) = &change.teachers {
        sqlx::query("DELETE FROM group_teachers WHERE world_id = ?")
            .bind(id)
            .execute(&mut *tx)
            .await?;
        for account in accounts {
            let teacher: Option<i64> =
                sqlx::query_scalar("SELECT 1 FROM teacher_worlds WHERE account = ? LIMIT 1")
                    .bind(account)
                    .fetch_optional(&mut *tx)
                    .await?;
            if teacher.is_none() {
                return Ok(Err(ChangeError::UnknownTeacher(account.clone())));
            }
            sqlx::query("INSERT OR IGNORE INTO group_teachers (world_id, account) VALUES (?, ?)")
                .bind(id)
                .bind(account)
                .execute(&mut *tx)
                .await?;
        }
    }
    tx.commit().await?;
    Ok(Ok(()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, worlds};

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|name| (*name).to_owned()).collect()
    }

    async fn refuse(pool: &SqlitePool, why: &str) {
        let job = jobs::take_waiting_for_agent(pool).await.unwrap();
        let result = lep_protocol::world::JobResult {
            ok: false,
            message: why.to_owned(),
        };
        jobs::finish_for_agent(pool, &job[0].id, &result)
            .await
            .unwrap();
    }

    async fn only_group(pool: &SqlitePool) -> Group {
        // "leitung" is made school administration by the caller.
        let mut all = visible_to(pool, "leitung").await.unwrap();
        all.retain(|group| group.name != "Erste");
        assert_eq!(all.len(), 1);
        all.remove(0)
    }

    /// A first world that was set up by hand, with "leitung" as school
    /// administration, and an agent.
    async fn school() -> SqlitePool {
        let pool = db::open_in_memory().await.unwrap();
        let (first, _) = worlds::add(&pool, "Erste").await.unwrap();
        set_school_admins(&pool, &first.id, &["leitung".to_owned()])
            .await
            .unwrap();
        game_server::rekey(&pool).await.unwrap();
        pool
    }

    #[tokio::test]
    async fn a_new_group_waits_for_the_agent_and_then_runs() {
        let pool = school().await;
        let id = create(&pool, " Klasse 7b ").await.unwrap().unwrap();

        let group = only_group(&pool).await;
        assert_eq!(group.id, id);
        assert_eq!(group.name, "Klasse 7b");
        assert_eq!(group.world, WorldSetup::Pending);
        assert_eq!(group.port, None);

        // The job carries a key the world will be known by.
        let waiting = jobs::take_waiting_for_agent(&pool).await.unwrap();
        assert_eq!(waiting.len(), 1);
        let payload: CreateWorld = serde_json::from_value(waiting[0].payload.clone()).unwrap();
        assert_eq!(payload.world, id);
        let found = worlds::find_by_key(&pool, &payload.bridge_key)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(found.id, id);

        // Done, but not reported yet: still waiting.
        let done = lep_protocol::world::JobResult {
            ok: true,
            message: "created on port 30000, and it runs".to_owned(),
        };
        jobs::finish_for_agent(&pool, &waiting[0].id, &done)
            .await
            .unwrap();
        assert_eq!(only_group(&pool).await.world, WorldSetup::Pending);

        let mut state = lep_protocol::agent::WorldState {
            id: id.clone(),
            port: 30000,
            template: "bdbbf00c8a29".to_owned(),
            running: true,
        };
        worlds::note_agent_state(&pool, std::slice::from_ref(&state), None)
            .await
            .unwrap();
        let group = only_group(&pool).await;
        assert_eq!(group.world, WorldSetup::Running);
        assert_eq!(group.port, Some(30000));

        state.running = false;
        worlds::note_agent_state(&pool, &[state], None)
            .await
            .unwrap();
        assert_eq!(only_group(&pool).await.world, WorldSetup::Stopped);
    }

    #[tokio::test]
    async fn the_world_of_a_group_is_started_and_stopped() {
        let pool = school().await;
        let id = create(&pool, "Klasse 7b").await.unwrap().unwrap();
        let by_hand = worlds::find_by_name(&pool, "Erste").await.unwrap().unwrap();

        // A world the agent does not run cannot be steered.
        for world in [&id, &by_hand.id] {
            assert_eq!(
                steer(&pool, world, WorldStep::Stop).await.unwrap(),
                Err(SteerError::NotRun)
            );
        }
        assert_eq!(
            steer(&pool, "no-such-group", WorldStep::Stop)
                .await
                .unwrap(),
            Err(SteerError::NotFound)
        );

        let created = jobs::take_waiting_for_agent(&pool).await.unwrap();
        let fine = lep_protocol::world::JobResult {
            ok: true,
            message: String::new(),
        };
        jobs::finish_for_agent(&pool, &created[0].id, &fine)
            .await
            .unwrap();
        let state = lep_protocol::agent::WorldState {
            id: id.clone(),
            port: 30000,
            template: "bdbbf00c8a29".to_owned(),
            running: true,
        };
        worlds::note_agent_state(&pool, &[state], None)
            .await
            .unwrap();
        assert_eq!(only_group(&pool).await.steering, None);

        steer(&pool, &id, WorldStep::Stop).await.unwrap().unwrap();
        assert_eq!(only_group(&pool).await.steering, Some(WorldStep::Stop));
        let waiting = jobs::take_waiting_for_agent(&pool).await.unwrap();
        assert_eq!(waiting.len(), 1);
        assert_eq!(waiting[0].kind, JOB_STOP_WORLD);
        assert_eq!(waiting[0].payload["world"], id);

        jobs::finish_for_agent(&pool, &waiting[0].id, &fine)
            .await
            .unwrap();
        let group = only_group(&pool).await;
        assert_eq!(group.steering, None);
        assert_eq!(group.step_refusal, None);

        // A refusal is shown until the next attempt.
        steer(&pool, &id, WorldStep::Start).await.unwrap().unwrap();
        refuse(&pool, "the world was started, but ended at once").await;
        let group = only_group(&pool).await;
        assert_eq!(group.steering, None);
        assert_eq!(
            group.step_refusal.as_deref(),
            Some("the world was started, but ended at once")
        );
        steer(&pool, &id, WorldStep::Restart)
            .await
            .unwrap()
            .unwrap();
        let group = only_group(&pool).await;
        assert_eq!(group.steering, Some(WorldStep::Restart));
        assert_eq!(group.step_refusal, None);
    }

    #[tokio::test]
    async fn the_agent_fixes_the_address_of_its_worlds() {
        let pool = school().await;
        let id = create(&pool, "Klasse 7b").await.unwrap().unwrap();
        let by_hand = worlds::find_by_name(&pool, "Erste").await.unwrap().unwrap();
        let state = lep_protocol::agent::WorldState {
            id: id.clone(),
            port: 30000,
            template: "bdbbf00c8a29".to_owned(),
            running: true,
        };

        // Without a name of the game server the address is entered by
        // hand, also for a world of the agent.
        worlds::note_agent_state(&pool, std::slice::from_ref(&state), None)
            .await
            .unwrap();
        assert!(!only_group(&pool).await.address_fixed);
        change(&pool, &id, &address("192.0.2.10, Port 30000"))
            .await
            .unwrap()
            .unwrap();

        // The agent names the game server: its word counts from now on.
        let report = lep_protocol::agent::AgentReport {
            version: "0.1.0".to_owned(),
            free_disk_bytes: 1,
            template: None,
            worlds: vec![state.clone()],
            host: Some("spiel.schule.example".to_owned()),
        };
        game_server::note_report(&pool, &report).await.unwrap();
        worlds::note_agent_state(&pool, &[state], report.host.as_deref())
            .await
            .unwrap();
        let group = only_group(&pool).await;
        assert!(group.address_fixed);
        assert_eq!(
            group.address.as_deref(),
            Some("spiel.schule.example, Port 30000")
        );
        assert_eq!(
            change(&pool, &id, &address("somewhere else"))
                .await
                .unwrap(),
            Err(ChangeError::InvalidAddress)
        );

        // A world that was set up by hand keeps its address by hand.
        let groups = visible_to(&pool, "leitung").await.unwrap();
        let first = groups.iter().find(|group| group.id == by_hand.id).unwrap();
        assert!(!first.address_fixed);
        change(&pool, &by_hand.id, &address("192.0.2.10, Port 30005"))
            .await
            .unwrap()
            .unwrap();
    }

    #[tokio::test]
    async fn a_group_needs_a_free_name_and_an_agent() {
        let pool = db::open_in_memory().await.unwrap();
        assert_eq!(
            create(&pool, "7b").await.unwrap(),
            Err(CreateError::NoGameServer)
        );
        game_server::rekey(&pool).await.unwrap();
        for name in ["", "   ", &"x".repeat(61), "7\nb"] {
            assert_eq!(
                create(&pool, name).await.unwrap(),
                Err(CreateError::InvalidName)
            );
        }
        create(&pool, "Klasse 7b").await.unwrap().unwrap();
        assert_eq!(
            create(&pool, "klasse 7B").await.unwrap(),
            Err(CreateError::NameTaken)
        );
        // Nothing was stored for the attempts that failed.
        assert_eq!(worlds::list(&pool).await.unwrap().len(), 1);
        assert_eq!(jobs::take_waiting_for_agent(&pool).await.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn a_refused_group_can_be_tried_again() {
        let pool = school().await;
        let id = create(&pool, "Klasse 7b").await.unwrap().unwrap();
        // Not refused yet: nothing to try again or to discard.
        assert_eq!(
            retry(&pool, &id).await.unwrap(),
            Err(RefusedError::NotRefused)
        );
        assert_eq!(
            discard(&pool, &id).await.unwrap(),
            Err(RefusedError::NotRefused)
        );

        let first = jobs::take_waiting_for_agent(&pool).await.unwrap();
        let old_key = first[0].payload["bridge_key"].as_str().unwrap().to_owned();
        refuse(&pool, "no port is free").await;
        let group = only_group(&pool).await;
        assert_eq!(group.world, WorldSetup::Refused);
        assert_eq!(group.refusal.as_deref(), Some("no port is free"));

        retry(&pool, &id).await.unwrap().unwrap();
        assert_eq!(only_group(&pool).await.world, WorldSetup::Pending);
        let second = jobs::take_waiting_for_agent(&pool).await.unwrap();
        assert_eq!(second.len(), 1);
        // The world gets a new key, and the old one is worth nothing.
        let new_key = second[0].payload["bridge_key"].as_str().unwrap();
        assert_ne!(new_key, old_key);
        assert!(worlds::find_by_key(&pool, &old_key)
            .await
            .unwrap()
            .is_none());
        assert!(worlds::find_by_key(&pool, new_key).await.unwrap().is_some());
    }

    #[tokio::test]
    async fn only_a_refused_group_can_be_discarded() {
        let pool = school().await;
        let (by_hand, _) = worlds::add(&pool, "Von Hand").await.unwrap();
        assert_eq!(
            discard(&pool, &by_hand.id).await.unwrap(),
            Err(RefusedError::NotRefused)
        );
        assert_eq!(
            discard(&pool, "no-such-group").await.unwrap(),
            Err(RefusedError::NotFound)
        );
        assert_eq!(
            retry(&pool, "no-such-group").await.unwrap(),
            Err(RefusedError::NotFound)
        );

        let id = create(&pool, "Probe").await.unwrap().unwrap();
        refuse(&pool, "the settings of the agent name no admin").await;
        assert_eq!(discard(&pool, &id).await.unwrap(), Ok("Probe".to_owned()));
        let names: Vec<String> = worlds::list(&pool)
            .await
            .unwrap()
            .into_iter()
            .map(|world| world.name)
            .collect();
        assert_eq!(names, ["Erste", "Von Hand"]);
        // Its jobs went with it, and the name is free again.
        let left: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM jobs")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(left, 0);
        create(&pool, "Probe").await.unwrap().unwrap();

        // A world that exists is never discarded, whatever its jobs say.
        let running = create(&pool, "Klasse 8a").await.unwrap().unwrap();
        let state = lep_protocol::agent::WorldState {
            id: running.clone(),
            port: 30001,
            template: "bdbbf00c8a29".to_owned(),
            running: false,
        };
        worlds::note_agent_state(&pool, &[state], None)
            .await
            .unwrap();
        refuse(&pool, "created on port 30001, but it could not be started").await;
        assert_eq!(
            discard(&pool, &running).await.unwrap(),
            Err(RefusedError::NotRefused)
        );
    }

    fn rename(name: &str) -> GroupChange {
        GroupChange {
            name: Some(name.to_owned()),
            teachers: None,
            address: None,
        }
    }

    fn assign(list: &[&str]) -> GroupChange {
        GroupChange {
            name: None,
            teachers: Some(names(list)),
            address: None,
        }
    }

    fn address(text: &str) -> GroupChange {
        GroupChange {
            name: None,
            teachers: None,
            address: Some(text.to_owned()),
        }
    }

    #[tokio::test]
    async fn a_group_can_get_the_address_of_its_world() {
        let (pool, first, _) = setup().await;
        let shown = |pool: SqlitePool, id: String| async move {
            find_visible(&pool, "leitung", &id)
                .await
                .unwrap()
                .unwrap()
                .address
        };
        assert_eq!(shown(pool.clone(), first.clone()).await, None);

        change(
            &pool,
            &first,
            &address("  spiel.schule.example, Port 30000 "),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(
            shown(pool.clone(), first.clone()).await.as_deref(),
            Some("spiel.schule.example, Port 30000")
        );

        for bad in ["zeile\nzwei".to_owned(), "x".repeat(MAX_ADDRESS + 1)] {
            assert_eq!(
                change(&pool, &first, &address(&bad)).await.unwrap(),
                Err(ChangeError::InvalidAddress)
            );
        }
        // An empty text removes it.
        change(&pool, &first, &address("  "))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(shown(pool.clone(), first.clone()).await, None);
    }

    /// Two worlds. "leitung" is school administration and teacher,
    /// "lehrer1" and "lehrer2" are teachers.
    async fn setup() -> (SqlitePool, String, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (first, _) = worlds::add(&pool, "7b").await.unwrap();
        let (second, _) = worlds::add(&pool, "8a").await.unwrap();
        teachers::set_holders(&pool, &first.id, &names(&["leitung", "lehrer1", "lehrer2"]))
            .await
            .unwrap();
        set_school_admins(&pool, &first.id, &names(&["leitung", "not valid"]))
            .await
            .unwrap();
        (pool, first.id, second.id)
    }

    fn ids(groups: &[Group]) -> Vec<&str> {
        groups.iter().map(|group| group.name.as_str()).collect()
    }

    #[tokio::test]
    async fn the_worlds_say_who_is_school_administration() {
        let (pool, first, second) = setup().await;
        assert!(is_school_admin(&pool, "leitung").await.unwrap());
        assert!(!is_school_admin(&pool, "lehrer1").await.unwrap());
        assert!(!is_school_admin(&pool, "not valid").await.unwrap());

        // One world is enough, and the list of a world replaces its old one.
        set_school_admins(&pool, &second, &names(&["lehrer1"]))
            .await
            .unwrap();
        assert!(is_school_admin(&pool, "lehrer1").await.unwrap());
        set_school_admins(&pool, &second, &[]).await.unwrap();
        assert!(!is_school_admin(&pool, "lehrer1").await.unwrap());
        set_school_admins(&pool, &first, &[]).await.unwrap();
        assert!(!is_school_admin(&pool, "leitung").await.unwrap());
    }

    #[tokio::test]
    async fn teachers_see_their_groups_and_the_administration_all() {
        let (pool, first, second) = setup().await;
        assert_eq!(
            ids(&visible_to(&pool, "leitung").await.unwrap()),
            ["7b", "8a"]
        );
        assert!(visible_to(&pool, "lehrer1").await.unwrap().is_empty());
        assert!(visible_to(&pool, "fremd").await.unwrap().is_empty());

        change(&pool, &second, &assign(&["lehrer1", "lehrer2"]))
            .await
            .unwrap()
            .unwrap();
        change(&pool, &first, &assign(&["lehrer2"]))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(ids(&visible_to(&pool, "lehrer1").await.unwrap()), ["8a"]);
        assert_eq!(
            ids(&visible_to(&pool, "lehrer2").await.unwrap()),
            ["7b", "8a"]
        );

        let group = find_visible(&pool, "lehrer1", &second)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(group.teachers, ["lehrer1", "lehrer2"]);
        assert_eq!(group.last_seen_at, None);
        assert_eq!(find_visible(&pool, "lehrer1", &first).await.unwrap(), None);
        assert_eq!(
            find_visible(&pool, "leitung", "no-such-id").await.unwrap(),
            None
        );
    }

    #[tokio::test]
    async fn assigning_replaces_the_list() {
        let (pool, first, _) = setup().await;
        change(&pool, &first, &assign(&["lehrer1", "lehrer2"]))
            .await
            .unwrap()
            .unwrap();
        change(&pool, &first, &assign(&["lehrer2", "lehrer2"]))
            .await
            .unwrap()
            .unwrap();
        let group = find_visible(&pool, "leitung", &first)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(group.teachers, ["lehrer2"]);
        change(&pool, &first, &assign(&[])).await.unwrap().unwrap();
        assert!(visible_to(&pool, "lehrer2").await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn only_teachers_can_be_assigned_and_nothing_is_done_by_halves() {
        let (pool, first, _) = setup().await;
        change(&pool, &first, &assign(&["lehrer1"]))
            .await
            .unwrap()
            .unwrap();
        let both = GroupChange {
            name: Some("7c".to_owned()),
            teachers: Some(names(&["lehrer2", "schueler1"])),
            address: Some("spiel.schule.example".to_owned()),
        };
        assert_eq!(
            change(&pool, &first, &both).await.unwrap(),
            Err(ChangeError::UnknownTeacher("schueler1".to_owned()))
        );
        let group = find_visible(&pool, "leitung", &first)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(group.name, "7b");
        assert_eq!(group.teachers, ["lehrer1"]);
        assert_eq!(
            assignable(&pool).await.unwrap(),
            ["lehrer1", "lehrer2", "leitung"]
        );
    }

    #[tokio::test]
    async fn a_group_can_be_renamed() {
        let (pool, first, second) = setup().await;
        change(&pool, &first, &rename("  Klasse 7b  "))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            ids(&visible_to(&pool, "leitung").await.unwrap()),
            ["8a", "Klasse 7b"]
        );
        assert!(worlds::find_by_name(&pool, "Klasse 7b")
            .await
            .unwrap()
            .is_some());

        // Its own name again is fine, also in other letter case.
        change(&pool, &first, &rename("klasse 7B"))
            .await
            .unwrap()
            .unwrap();
        for (name, expected) in [
            ("8A", ChangeError::NameTaken),
            ("", ChangeError::InvalidName),
            ("   ", ChangeError::InvalidName),
            ("7b\nx", ChangeError::InvalidName),
        ] {
            assert_eq!(
                change(&pool, &first, &rename(name)).await.unwrap(),
                Err(expected)
            );
        }
        let long = "x".repeat(MAX_NAME + 1);
        assert_eq!(
            change(&pool, &first, &rename(&long)).await.unwrap(),
            Err(ChangeError::InvalidName)
        );
        assert_eq!(
            change(&pool, "no-such-id", &rename("9c")).await.unwrap(),
            Err(ChangeError::NotFound)
        );
        assert_eq!(
            ids(&visible_to(&pool, "leitung").await.unwrap()),
            ["8a", "klasse 7B"]
        );
        let _ = second;
    }
}
