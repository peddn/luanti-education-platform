//! One password for a teacher in all worlds: what the worlds report and
//! what the backend orders in return. Called without a network.

use lep_backend::app::AppState;
use lep_backend::{db, events, jobs, staff, staff_passwords, worlds};
use lep_protocol::world::{Event, EventOutcome, JobResult, StaffPassword, StaffPasswords};
use serde_json::{json, Value};
use sqlx::SqlitePool;

const E1: &str = "#1#c2FsdDE#dmVyaWZpZXIx";
const E2: &str = "#1#c2FsdDI#dmVyaWZpZXIy";
const E3: &str = "#1#c2FsdDM#dmVyaWZpZXIz";

struct Setup {
    pool: SqlitePool,
    first: String,
    second: String,
}

fn account(name: &str, entry: &str, version: u32, changed: bool) -> StaffPassword {
    StaffPassword {
        name: name.to_owned(),
        // Without an entry: the world keeps what it has to itself.
        entry: (!entry.is_empty()).then(|| entry.to_owned()),
        version,
        changed,
    }
}

impl Setup {
    /// Two worlds and the teacher "frau_meier", ordered in both. What
    /// the backend keeps of the start password is replaced by E1, so the
    /// tests can name it.
    async fn new() -> Self {
        let pool = db::open_in_memory().await.unwrap();
        let (first, _) = worlds::add(&pool, "7b").await.unwrap();
        let (second, _) = worlds::add(&pool, "8a").await.unwrap();
        staff::create(&pool, "frau_meier", "leitung")
            .await
            .unwrap()
            .unwrap();
        sqlx::query("UPDATE staff_accounts SET password_entry = ?")
            .bind(E1)
            .execute(&pool)
            .await
            .unwrap();
        Self {
            pool,
            first: first.id,
            second: second.id,
        }
    }

    /// A world reports its teachers. Returns the worlds that were woken.
    async fn report(&self, world: &str, accounts: Vec<StaffPassword>) -> Vec<String> {
        staff_passwords::note(&self.pool, world, &StaffPasswords { accounts })
            .await
            .unwrap()
            .into_iter()
            .collect()
    }

    /// A world fetches its jobs and answers each. Returns kind and
    /// payload of what it got.
    async fn work(&self, world: &str, ok: bool) -> Vec<(String, Value)> {
        let waiting = jobs::take_waiting(&self.pool, world).await.unwrap();
        for job in &waiting {
            let result = JobResult {
                ok,
                message: if ok { "set" } else { "unknown" }.to_owned(),
            };
            assert!(jobs::finish(&self.pool, world, &job.id, &result)
                .await
                .unwrap());
        }
        waiting
            .into_iter()
            .map(|job| (job.kind, job.payload))
            .collect()
    }

    async fn kept(&self) -> (Option<String>, u32) {
        sqlx::query_as(
            "SELECT password_entry, password_version FROM staff_accounts
             WHERE account = 'frau_meier'",
        )
        .fetch_one(&self.pool)
        .await
        .unwrap()
    }

    /// The worlds that have the account, each with whether it is in step.
    async fn arrived(&self) -> Vec<(String, bool)> {
        let mut rows: Vec<(String, bool)> = sqlx::query_as(
            "SELECT worlds.name, in_step FROM staff_worlds
             JOIN worlds ON worlds.id = staff_worlds.world_id WHERE account = 'frau_meier'",
        )
        .fetch_all(&self.pool)
        .await
        .unwrap();
        rows.sort();
        rows
    }

    /// Both worlds have created the account and said so.
    async fn settled() -> Self {
        let setup = Self::new().await;
        for world in [&setup.first, &setup.second] {
            setup.work(world, true).await;
            assert!(setup
                .report(world, vec![account("frau_meier", E1, 1, false)])
                .await
                .is_empty());
        }
        setup
    }
}

fn entry_order(entry: &str, version: u32) -> (String, Value) {
    (
        "set_password_entry".to_owned(),
        json!({ "name": "frau_meier", "entry": entry, "version": version }),
    )
}

#[tokio::test]
async fn a_start_password_is_the_same_entry_everywhere() {
    let pool = db::open_in_memory().await.unwrap();
    let (first, _) = worlds::add(&pool, "7b").await.unwrap();
    let (second, _) = worlds::add(&pool, "8a").await.unwrap();
    let (slip, _) = staff::create(&pool, "frau_meier", "leitung")
        .await
        .unwrap()
        .unwrap();
    let (kept, version): (String, u32) =
        sqlx::query_as("SELECT password_entry, password_version FROM staff_accounts")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(kept.starts_with("#1#"), "{kept}");
    assert_eq!(version, 1);
    for world in [&first.id, &second.id] {
        let orders = jobs::take_waiting(&pool, world).await.unwrap();
        assert_eq!(orders.len(), 1);
        assert_eq!(
            orders[0].payload,
            json!({ "accounts": [{ "name": "frau_meier", "entry": kept }],
                "teacher": true, "by": "leitung", "version": 1 })
        );
        assert!(!orders[0].payload.to_string().contains(&slip.password));
    }

    // The worlds have it and say so: nothing is left to do.
    let setup = Setup::settled().await;
    assert_eq!(setup.kept().await, (Some(E1.to_owned()), 1));
    assert_eq!(
        setup.arrived().await,
        vec![("7b".to_owned(), true), ("8a".to_owned(), true)]
    );
    assert!(setup.work(&setup.first, true).await.is_empty());
    assert!(setup.work(&setup.second, true).await.is_empty());
}

#[tokio::test]
async fn a_password_changed_in_one_world_arrives_in_the_others() {
    let setup = Setup::settled().await;
    let mut woken = setup
        .report(&setup.second, vec![account("frau_meier", E3, 1, true)])
        .await;
    woken.sort();
    let mut both = vec![setup.first.clone(), setup.second.clone()];
    both.sort();
    assert_eq!(woken, both);
    assert_eq!(setup.kept().await, (Some(E3.to_owned()), 2));

    // An old report of the first world that arrives late changes
    // nothing, before its order is done and after.
    assert!(setup
        .report(&setup.first, vec![account("frau_meier", E1, 1, false)])
        .await
        .is_empty());
    assert_eq!(
        setup.work(&setup.first, true).await,
        vec![entry_order(E3, 2)]
    );
    assert_eq!(
        setup
            .report(&setup.first, vec![account("frau_meier", E1, 1, false)])
            .await,
        vec![setup.first.clone()]
    );
    assert_eq!(setup.kept().await, (Some(E3.to_owned()), 2));
    assert_eq!(
        setup.work(&setup.first, true).await,
        vec![entry_order(E3, 2)]
    );

    // The world it came from learns the version.
    assert_eq!(
        setup.work(&setup.second, true).await,
        vec![entry_order(E3, 2)]
    );
    for world in [&setup.first, &setup.second] {
        assert!(setup
            .report(world, vec![account("frau_meier", E3, 2, false)])
            .await
            .is_empty());
    }
    assert_eq!(
        setup.arrived().await,
        vec![("7b".to_owned(), true), ("8a".to_owned(), true)]
    );

    // The entry is gone from the orders that were answered.
    let left: Vec<String> =
        sqlx::query_scalar("SELECT payload FROM jobs WHERE kind = 'set_password_entry'")
            .fetch_all(&setup.pool)
            .await
            .unwrap();
    assert!(!left.is_empty());
    assert!(left.iter().all(|payload| payload == "{}"), "{left:?}");
}

#[tokio::test]
async fn a_change_on_top_of_an_old_password_loses() {
    let setup = Setup::settled().await;
    setup
        .report(&setup.second, vec![account("frau_meier", E3, 1, true)])
        .await;
    setup.work(&setup.second, true).await;
    // The first world has not fetched the new password yet, and somebody
    // changes the old one there. The order that waits for it stays.
    assert!(setup
        .report(&setup.first, vec![account("frau_meier", E2, 1, true)])
        .await
        .is_empty());
    assert_eq!(setup.kept().await, (Some(E3.to_owned()), 2));
    assert_eq!(
        setup.work(&setup.first, true).await,
        vec![entry_order(E3, 2)]
    );
}

#[tokio::test]
async fn a_world_with_the_right_password_learns_its_version() {
    let setup = Setup::settled().await;
    // The entry fits, but the world says it was changed there: it does
    // not know the version it has.
    assert_eq!(
        setup
            .report(&setup.first, vec![account("frau_meier", E1, 0, true)])
            .await,
        vec![setup.first.clone()]
    );
    assert_eq!(setup.kept().await, (Some(E1.to_owned()), 1));
    assert_eq!(
        setup.work(&setup.first, true).await,
        vec![entry_order(E1, 1)]
    );
}

#[tokio::test]
async fn a_new_world_gets_the_teachers_with_their_password() {
    let setup = Setup::settled().await;
    let (third, _) = worlds::add(&setup.pool, "9c").await.unwrap();
    assert_eq!(
        setup.report(&third.id, Vec::new()).await,
        vec![third.id.clone()]
    );
    // Asked once only, whatever the world makes of it.
    assert!(setup.report(&third.id, Vec::new()).await.is_empty());
    assert_eq!(
        setup.work(&third.id, true).await,
        vec![(
            "create_accounts".to_owned(),
            json!({ "accounts": [{ "name": "frau_meier", "entry": E1 }],
                "teacher": true, "by": "leitung", "version": 1 })
        )]
    );
    assert!(setup
        .report(&third.id, vec![account("frau_meier", E1, 1, false)])
        .await
        .is_empty());
    assert_eq!(setup.arrived().await.len(), 3);

    // A world that lost the account is not counted any more.
    assert!(setup.report(&third.id, Vec::new()).await.is_empty());
    assert_eq!(setup.arrived().await.len(), 2);
}

#[tokio::test]
async fn a_new_start_password_goes_to_every_world() {
    let setup = Setup::settled().await;
    // The second world waits for a password from the first one.
    setup
        .report(&setup.first, vec![account("frau_meier", E2, 1, true)])
        .await;
    setup.work(&setup.first, true).await;
    let (slip, worlds) = staff::reset_password(&setup.pool, "frau_meier", "leitung")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(worlds.len(), 2);
    let (kept, version) = setup.kept().await;
    let kept = kept.unwrap();
    assert_eq!(version, 3);
    assert!(kept.starts_with("#1#") && kept != E2, "{kept}");
    assert!(setup.arrived().await.iter().all(|(_, in_step)| !in_step));

    // An old report changes nothing, whatever it says.
    for changed in [false, true] {
        assert!(setup
            .report(&setup.first, vec![account("frau_meier", E2, 2, changed)])
            .await
            .is_empty());
    }
    assert_eq!(setup.kept().await, (Some(kept.clone()), 3));

    // The order that was overtaken is gone, the new one names who
    // ordered it.
    let order = json!({ "name": "frau_meier", "entry": kept, "version": 3, "by": "leitung" });
    for world in [&setup.first, &setup.second] {
        let got = setup.work(world, true).await;
        assert_eq!(got, vec![("set_password_entry".to_owned(), order.clone())]);
        assert!(!got[0].1.to_string().contains(&slip.password));
        assert!(setup
            .report(world, vec![account("frau_meier", &kept, 3, false)])
            .await
            .is_empty());
    }
    assert!(setup.arrived().await.iter().all(|(_, in_step)| *in_step));
}

#[tokio::test]
async fn a_password_set_by_command_stays_in_its_world() {
    let setup = Setup::settled().await;
    // The engine stores it in a form that never leaves the world. It is
    // not passed on and not undone.
    assert!(setup
        .report(&setup.first, vec![account("frau_meier", "", 1, true)])
        .await
        .is_empty());
    assert_eq!(setup.kept().await, (Some(E1.to_owned()), 1));
    assert_eq!(
        setup.arrived().await,
        vec![("7b".to_owned(), false), ("8a".to_owned(), true)]
    );
    // The next password from anywhere counts there again.
    setup
        .report(&setup.second, vec![account("frau_meier", E3, 1, true)])
        .await;
    assert_eq!(
        setup.work(&setup.first, true).await,
        vec![entry_order(E3, 2)]
    );

    // An account that still has the old form without a change of its
    // own gets the entry that counts.
    assert_eq!(
        setup
            .report(&setup.first, vec![account("frau_meier", "", 1, false)])
            .await,
        vec![setup.first.clone()]
    );
    assert_eq!(
        setup.work(&setup.first, true).await,
        vec![entry_order(E3, 2)]
    );
}

#[tokio::test]
async fn an_account_from_before_is_kept_in_step_from_its_first_own_password() {
    let setup = Setup::settled().await;
    sqlx::query("UPDATE staff_accounts SET password_entry = NULL, password_version = 0")
        .execute(&setup.pool)
        .await
        .unwrap();
    // Every world hashed the start password for itself, back then.
    for world in [&setup.first, &setup.second] {
        assert!(setup
            .report(world, vec![account("frau_meier", "", 0, true)])
            .await
            .is_empty());
    }
    assert_eq!(setup.kept().await, (None, 0));
    let mut woken = setup
        .report(&setup.second, vec![account("frau_meier", E2, 0, true)])
        .await;
    woken.sort();
    let mut both = vec![setup.first.clone(), setup.second.clone()];
    both.sort();
    assert_eq!(woken, both);
    assert_eq!(setup.kept().await, (Some(E2.to_owned()), 1));
    assert_eq!(
        setup.work(&setup.first, true).await,
        vec![entry_order(E2, 1)]
    );
}

#[tokio::test]
async fn only_teachers_created_here_are_kept_in_step() {
    let setup = Setup::settled().await;
    sqlx::query(
        "INSERT INTO students (account, world_id, state, created_at, used)
         VALUES ('klugeEule', ?, 'active', 0, 1)",
    )
    .bind(&setup.first)
    .execute(&setup.pool)
    .await
    .unwrap();
    // A teacher made in the game and a student with a privilege.
    assert!(setup
        .report(
            &setup.first,
            vec![
                account("lehrer1", E2, 0, true),
                account("klugeEule", E2, 0, true),
                account("frau_meier", E1, 1, false),
            ]
        )
        .await
        .is_empty());
    assert_eq!(setup.kept().await, (Some(E1.to_owned()), 1));
    let jobs: i64 = sqlx::query_scalar("SELECT count(*) FROM jobs WHERE finished_at IS NULL")
        .fetch_one(&setup.pool)
        .await
        .unwrap();
    assert_eq!(jobs, 0);

    // An entry that is none is never passed on: the world gets the one
    // that counts.
    assert_eq!(
        setup
            .report(
                &setup.first,
                vec![account("frau_meier", "#1#no entry", 1, false)]
            )
            .await,
        vec![setup.first.clone()]
    );
    assert_eq!(setup.kept().await, (Some(E1.to_owned()), 1));
    assert_eq!(
        setup.work(&setup.first, true).await,
        vec![entry_order(E1, 1)]
    );

    // While the account is being deleted, nothing is passed on.
    staff::remove(&setup.pool, "frau_meier", "leitung")
        .await
        .unwrap()
        .unwrap();
    assert!(setup
        .report(&setup.second, vec![account("frau_meier", E3, 1, true)])
        .await
        .is_empty());
    assert_eq!(setup.kept().await, (Some(E1.to_owned()), 1));

    // Deleted: nothing about the password stays.
    staff::forget(&setup.pool, "frau_meier").await.unwrap();
    assert!(setup.arrived().await.is_empty());
}

#[tokio::test]
async fn a_backend_that_was_set_up_again_catches_up_with_the_versions() {
    let setup = Setup::settled().await;
    setup
        .report(&setup.first, vec![account("frau_meier", E3, 7, true)])
        .await;
    assert_eq!(setup.kept().await, (Some(E3.to_owned()), 8));
}

#[tokio::test]
async fn the_report_arrives_as_an_event() {
    let setup = Setup::settled().await;
    let app = AppState::new(setup.pool.clone());
    let event = |id: &str, payload| Event {
        id: id.to_owned(),
        kind: "staff_passwords".to_owned(),
        time: 1000,
        payload,
    };
    let changed = event(
        "e1",
        json!({ "accounts": [{ "name": "frau_meier", "entry": E3, "version": 1,
            "changed": true }] }),
    );
    assert_eq!(
        events::take_in(&app, &setup.first, &changed).await.unwrap(),
        EventOutcome::Accepted
    );
    assert_eq!(setup.kept().await, (Some(E3.to_owned()), 2));
    // A world without teachers sends an empty list, which arrives as
    // nothing at all.
    let (third, _) = worlds::add(&setup.pool, "9c").await.unwrap();
    assert_eq!(
        events::take_in(&app, &third.id, &event("e2", Value::Null))
            .await
            .unwrap(),
        EventOutcome::Accepted
    );
    assert_eq!(
        setup.work(&third.id, true).await[0].1["accounts"][0]["entry"],
        E3
    );
    assert_eq!(
        events::take_in(&app, &third.id, &event("e3", json!({ "accounts": 5 })))
            .await
            .unwrap(),
        EventOutcome::Invalid
    );
}
