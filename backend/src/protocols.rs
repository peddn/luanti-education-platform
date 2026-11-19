//! The protocols of a world for the browser: chat, signs, rewards, the
//! desk and display names. The worlds write them, the backend mirrors
//! every entry, and here they are read, filtered and exported.

use std::collections::BTreeMap;

use anyhow::Result;
use lep_protocol::web::{ProtocolPage, ProtocolRow};
use sqlx::{QueryBuilder, Row, Sqlite, SqlitePool};

/// How many entries a page of a protocol has.
pub const PAGE: i64 = 100;
/// The most entries one export holds.
pub const MAX_EXPORT: i64 = 50_000;

/// The protocol that shows what teachers did. Only the administration
/// of the school may read it.
pub const DESK: &str = "desk";

/// Returns the columns of a protocol besides time and account, in the
/// order to show them, or `None` for a name that is no protocol.
pub fn columns(protocol: &str) -> Option<&'static [&'static str]> {
    Some(match protocol {
        "chat" => &["kind", "recipient", "text"],
        "signs" => &["pos", "text"],
        "rewards" => &["size", "reason", "module", "level", "task", "items"],
        "desk" => &["action", "targets"],
        "names" => &["action", "name", "by"],
        _ => return None,
    })
}

/// What narrows a protocol down.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Filter {
    /// Only entries of this account.
    pub account: Option<String>,
    /// Only entries from this time on, in seconds since 1970.
    pub since: Option<i64>,
}

/// Which part of the filtered entries is wanted.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Part {
    /// The newest entries.
    Newest,
    /// The entries older than the one with this id.
    Before(i64),
    /// The entries that arrived after the one with this id.
    After(i64),
}

fn select(world_id: &str, protocol: &str, filter: &Filter) -> QueryBuilder<Sqlite> {
    let mut query = QueryBuilder::new(
        "SELECT entries.id, entries.time, entries.account, entries.fields,
                display_names.name AS display_name
         FROM protocol_entries AS entries
         LEFT JOIN display_names ON display_names.world_id = entries.world_id
                                AND display_names.account = entries.account
         WHERE entries.world_id = ",
    );
    query.push_bind(world_id.to_owned());
    query
        .push(" AND entries.protocol = ")
        .push_bind(protocol.to_owned());
    if let Some(account) = &filter.account {
        query
            .push(" AND entries.account = ")
            .push_bind(account.clone())
            .push(" COLLATE NOCASE");
    }
    if let Some(since) = filter.since {
        query.push(" AND entries.time >= ").push_bind(since);
    }
    query
}

fn row_of(row: &sqlx::sqlite::SqliteRow) -> ProtocolRow {
    let fields: BTreeMap<String, String> =
        serde_json::from_str(row.get("fields")).unwrap_or_default();
    ProtocolRow {
        id: row.get("id"),
        time: row.get("time"),
        account: row.get("account"),
        display_name: row.get("display_name"),
        fields,
    }
}

/// Returns a part of a protocol of a world, newest entries first, or
/// `None` for a name that is no protocol.
pub async fn page(
    pool: &SqlitePool,
    world_id: &str,
    protocol: &str,
    filter: &Filter,
    part: Part,
) -> Result<Option<ProtocolPage>> {
    let Some(columns) = columns(protocol) else {
        return Ok(None);
    };
    let mut query = select(world_id, protocol, filter);
    match part {
        Part::Newest => {}
        Part::Before(id) => {
            query.push(" AND entries.id < ").push_bind(id);
        }
        Part::After(id) => {
            query.push(" AND entries.id > ").push_bind(id);
        }
    }
    // One more than a page, to know whether there are more.
    query
        .push(" ORDER BY entries.id DESC LIMIT ")
        .push_bind(PAGE + 1);
    let rows = query.build().fetch_all(pool).await?;
    let more = rows.len() as i64 > PAGE;
    Ok(Some(ProtocolPage {
        columns: columns.iter().map(|name| (*name).to_owned()).collect(),
        entries: rows.iter().take(PAGE as usize).map(row_of).collect(),
        more,
    }))
}

/// Writes a time as text, in UTC: "2026-11-19 12:34:56".
fn utc(time: i64) -> String {
    let days = time.div_euclid(86_400);
    let seconds = time.rem_euclid(86_400);
    // Days since 1970 to a date, after Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let day_of_era = z.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 {
        month_index + 3
    } else {
        month_index - 9
    };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02} {:02}:{:02}:{:02}",
        seconds / 3_600,
        seconds % 3_600 / 60,
        seconds % 60
    )
}

/// Writes one cell of a CSV file. Text that a spreadsheet would take
/// for a formula gets a leading apostrophe: the texts are typed by
/// students, and the file is opened by teachers.
fn cell(text: &str) -> String {
    let guarded = if text.starts_with(['=', '+', '-', '@', '\t', '\r']) {
        format!("'{text}")
    } else {
        text.to_owned()
    };
    if guarded.contains([';', '"', '\n', '\r']) {
        format!("\"{}\"", guarded.replace('"', "\"\""))
    } else {
        guarded
    }
}

/// Returns the filtered entries of a protocol as a CSV file, oldest
/// first, or `None` for a name that is no protocol. Cells are separated
/// by semicolons, as the spreadsheets in schools here expect, and the
/// file starts with a mark that makes them read umlauts.
pub async fn export(
    pool: &SqlitePool,
    world_id: &str,
    protocol: &str,
    filter: &Filter,
) -> Result<Option<String>> {
    let Some(columns) = columns(protocol) else {
        return Ok(None);
    };
    let mut query = select(world_id, protocol, filter);
    query
        .push(" ORDER BY entries.id DESC LIMIT ")
        .push_bind(MAX_EXPORT);
    let rows = query.build().fetch_all(pool).await?;

    let mut file = String::from("\u{feff}time_utc;account;display_name");
    for column in columns {
        file.push(';');
        file.push_str(column);
    }
    file.push_str("\r\n");
    for row in rows.iter().rev().map(row_of) {
        file.push_str(&utc(row.time));
        file.push(';');
        file.push_str(&cell(&row.account));
        file.push(';');
        file.push_str(&cell(row.display_name.as_deref().unwrap_or_default()));
        for column in columns {
            file.push(';');
            file.push_str(&cell(row.fields.get(*column).map_or("", String::as_str)));
        }
        file.push_str("\r\n");
    }
    Ok(Some(file))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, state, worlds};
    use lep_protocol::world::{DisplayName, ProtocolEntry};

    async fn setup() -> (SqlitePool, String) {
        let pool = db::open_in_memory().await.unwrap();
        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        (pool, world.id)
    }

    async fn write(
        pool: &SqlitePool,
        world: &str,
        protocol: &str,
        time: i64,
        account: &str,
        fields: &[(&str, &str)],
    ) {
        let entry = ProtocolEntry {
            protocol: protocol.to_owned(),
            account: account.to_owned(),
            fields: fields
                .iter()
                .map(|(key, value)| ((*key).to_owned(), (*value).to_owned()))
                .collect(),
        };
        assert!(state::store_protocol_entry(pool, world, time, &entry)
            .await
            .unwrap());
    }

    fn texts(page: &ProtocolPage) -> Vec<&str> {
        page.entries
            .iter()
            .map(|row| row.fields["text"].as_str())
            .collect()
    }

    #[tokio::test]
    async fn shows_the_newest_entries_first_with_the_display_name_of_now() {
        let (pool, world) = setup().await;
        let (other, _) = worlds::add(&pool, "8a").await.unwrap();
        write(
            &pool,
            &world,
            "chat",
            100,
            "klugeEule",
            &[("kind", "chat"), ("text", "eins")],
        )
        .await;
        write(
            &pool,
            &world,
            "chat",
            200,
            "frohesReh",
            &[("kind", "chat"), ("text", "zwei")],
        )
        .await;
        write(
            &pool,
            &world,
            "signs",
            250,
            "klugeEule",
            &[("pos", "(1,2,3)"), ("text", "Schild")],
        )
        .await;
        write(
            &pool,
            &other.id,
            "chat",
            300,
            "klugeEule",
            &[("text", "fremd")],
        )
        .await;
        let name = DisplayName {
            account: "klugeEule".to_owned(),
            name: Some("Lena".to_owned()),
            changed_at: Some(150),
            locked: false,
        };
        crate::display_names::store(&pool, &world, 150, &name)
            .await
            .unwrap();

        let all = Filter::default();
        let chat = page(&pool, &world, "chat", &all, Part::Newest)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(chat.columns, ["kind", "recipient", "text"]);
        assert_eq!(texts(&chat), ["zwei", "eins"]);
        assert!(!chat.more);
        assert_eq!(chat.entries[0].display_name, None);
        // The name of now, also for what was written before it was chosen.
        assert_eq!(chat.entries[1].display_name.as_deref(), Some("Lena"));
        assert_eq!(chat.entries[1].time, 100);

        let signs = page(&pool, &world, "signs", &all, Part::Newest)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(texts(&signs), ["Schild"]);
        assert_eq!(
            page(&pool, &world, "passwords", &all, Part::Newest)
                .await
                .unwrap(),
            None
        );
    }

    #[tokio::test]
    async fn narrows_down_by_account_and_time() {
        let (pool, world) = setup().await;
        for (time, account, text) in [
            (100, "klugeEule", "a"),
            (200, "frohesReh", "b"),
            (300, "klugeEule", "c"),
        ] {
            write(&pool, &world, "chat", time, account, &[("text", text)]).await;
        }
        let of = |account: Option<&str>, since: Option<i64>| Filter {
            account: account.map(str::to_owned),
            since,
        };
        let get = |filter: Filter| {
            let pool = pool.clone();
            let world = world.clone();
            async move {
                let page = page(&pool, &world, "chat", &filter, Part::Newest)
                    .await
                    .unwrap()
                    .unwrap();
                texts(&page).join("")
            }
        };
        assert_eq!(get(of(Some("klugeEule"), None)).await, "ca");
        // The case of letters does not matter for the search.
        assert_eq!(get(of(Some("KLUGEEULE"), None)).await, "ca");
        assert_eq!(get(of(None, Some(200))).await, "cb");
        assert_eq!(get(of(Some("klugeEule"), Some(200))).await, "c");
        assert_eq!(get(of(Some("niemand"), None)).await, "");
        // A name is taken as it is, never as a pattern.
        assert_eq!(get(of(Some("kluge%"), None)).await, "");
    }

    #[tokio::test]
    async fn goes_through_a_long_protocol_page_by_page() {
        let (pool, world) = setup().await;
        for number in 1..=250 {
            write(
                &pool,
                &world,
                "chat",
                number,
                "klugeEule",
                &[("text", &number.to_string())],
            )
            .await;
        }
        let all = Filter::default();
        let first = page(&pool, &world, "chat", &all, Part::Newest)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(first.entries.len(), 100);
        assert!(first.more);
        assert_eq!(first.entries[0].fields["text"], "250");
        let last = first.entries.last().unwrap();
        assert_eq!(last.fields["text"], "151");

        let second = page(&pool, &world, "chat", &all, Part::Before(last.id))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(second.entries[0].fields["text"], "150");
        assert!(second.more);
        let third = page(
            &pool,
            &world,
            "chat",
            &all,
            Part::Before(second.entries.last().unwrap().id),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(third.entries.len(), 50);
        assert!(!third.more);

        // What arrived after an entry, for a page that is already open.
        write(&pool, &world, "chat", 251, "klugeEule", &[("text", "neu")]).await;
        let newer = page(
            &pool,
            &world,
            "chat",
            &all,
            Part::After(first.entries[0].id),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(texts(&newer), ["neu"]);
    }

    #[test]
    fn writes_times_in_utc() {
        assert_eq!(utc(0), "1970-01-01 00:00:00");
        assert_eq!(utc(1_700_000_000), "2023-11-14 22:13:20");
        assert_eq!(utc(951_782_399), "2000-02-28 23:59:59");
        assert_eq!(utc(951_782_400), "2000-02-29 00:00:00");
        assert_eq!(utc(1_795_089_600), "2026-11-19 12:00:00");
    }

    #[test]
    fn keeps_cells_apart_and_formulas_harmless() {
        assert_eq!(cell("hallo"), "hallo");
        assert_eq!(cell("a;b"), "\"a;b\"");
        assert_eq!(cell("sagt \"hi\""), "\"sagt \"\"hi\"\"\"");
        assert_eq!(cell("zwei\nZeilen"), "\"zwei\nZeilen\"");
        assert_eq!(cell("=SUMME(A1)"), "'=SUMME(A1)");
        assert_eq!(cell("+49 170"), "'+49 170");
        assert_eq!(cell("-1"), "'-1");
        assert_eq!(cell("@alle"), "'@alle");
        assert_eq!(cell("=1;2"), "\"'=1;2\"");
        // A comma is no separator here.
        assert_eq!(cell("a, b"), "a, b");
    }

    #[tokio::test]
    async fn exports_the_filtered_entries_oldest_first() {
        let (pool, world) = setup().await;
        write(
            &pool,
            &world,
            "chat",
            1_700_000_000,
            "klugeEule",
            &[("kind", "chat"), ("text", "hallo; du")],
        )
        .await;
        write(
            &pool,
            &world,
            "chat",
            1_700_000_060,
            "frohesReh",
            &[
                ("kind", "private"),
                ("recipient", "klugeEule"),
                ("text", "=1+1"),
            ],
        )
        .await;
        let all = Filter::default();
        let file = export(&pool, &world, "chat", &all).await.unwrap().unwrap();
        assert_eq!(
            file,
            "\u{feff}time_utc;account;display_name;kind;recipient;text\r\n\
             2023-11-14 22:13:20;klugeEule;;chat;;\"hallo; du\"\r\n\
             2023-11-14 22:14:20;frohesReh;;private;klugeEule;'=1+1\r\n"
        );
        let one = Filter {
            account: Some("frohesReh".to_owned()),
            since: None,
        };
        let file = export(&pool, &world, "chat", &one).await.unwrap().unwrap();
        assert_eq!(file.lines().count(), 2);
        assert_eq!(export(&pool, &world, "nonsense", &all).await.unwrap(), None);
    }
}
