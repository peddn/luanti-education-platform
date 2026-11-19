//! Groups: the worlds as teachers see them.
//!
//! A group is a world, one to one. The school administration sees every
//! group, renames groups and assigns teachers. Every other teacher sees
//! the groups they are assigned to. All of this is checked here, with
//! every request, not in the frontend.

use anyhow::Result;
use lep_protocol::web::{Group, GroupChange};
use sqlx::{Row, SqlitePool};

use crate::teachers;

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
        "SELECT id, name, last_seen_at, address FROM worlds
         WHERE ? OR EXISTS (SELECT 1 FROM group_teachers
                            WHERE group_teachers.world_id = worlds.id
                              AND group_teachers.account = ?)
         ORDER BY name COLLATE NOCASE, name",
    )
    .bind(everything)
    .bind(account)
    .fetch_all(pool)
    .await?;
    let mut groups = Vec::with_capacity(rows.len());
    for row in rows {
        let id: String = row.get("id");
        groups.push(Group {
            teachers: teachers_of(pool, &id).await?,
            id,
            name: row.get("name"),
            last_seen_at: row.get("last_seen_at"),
            address: row.get("address"),
        });
    }
    Ok(groups)
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
