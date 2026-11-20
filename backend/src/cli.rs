//! The commands of the program. Without a command it serves; the others
//! look after the database from the terminal.

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use lep_protocol::world::{JOB_PING, JOB_SYNC_STATE};
use serde_json::json;
use sqlx::SqlitePool;

use crate::config::Config;
use crate::mail::{self, Mailer};
use crate::{app, game_server, jobs, state, teachers, worlds};

#[derive(Debug, Parser)]
#[command(
    name = "lep-backend",
    version,
    about = "Backend of the Luanti Education Platform"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Run the web server. This is what happens without a command.
    Serve,
    /// Look after the worlds.
    World {
        #[command(subcommand)]
        command: WorldCommand,
    },
    /// Try out the mail server.
    Mail {
        #[command(subcommand)]
        command: MailCommand,
    },
    /// Look after the teachers and their web access.
    Teacher {
        #[command(subcommand)]
        command: TeacherCommand,
    },
    /// Look after the agent on the game server.
    Agent {
        #[command(subcommand)]
        command: AgentCommand,
    },
    /// Print the description of the interface, as in api/openapi.json.
    Openapi,
}

#[derive(Debug, Subcommand)]
pub enum AgentCommand {
    /// Give the agent a key and print it. The key is shown only now. A
    /// key that existed before stops working.
    Key,
    /// Show what the agent last said about the game server.
    Show,
}

/// Runs a command about the agent and returns what to print.
pub async fn run_agent(pool: &SqlitePool, command: AgentCommand) -> Result<String> {
    match command {
        AgentCommand::Key => {
            let key = game_server::rekey(pool).await?;
            Ok(format!(
                "New key for the agent:\nkey: {key}\nThe key is shown only now. It belongs \
                 into the settings of the agent, not into the repository. An older key \
                 no longer works."
            ))
        }
        AgentCommand::Show => {
            let Some(server) = game_server::describe(pool).await? else {
                return Ok("There is no key for the agent yet.".to_owned());
            };
            let Some(seen) = server.last_seen_at else {
                return Ok("The agent has a key, but never reported.".to_owned());
            };
            Ok(format!(
                "Game server: {}\nlast seen {} s ago\nagent version: {}\nfree disk space: {} MiB\n\
                 template for worlds: {}",
                if server.connected {
                    "connected"
                } else {
                    "out of reach"
                },
                (crate::clock::now() - seen).max(0),
                server.version.as_deref().unwrap_or("unknown"),
                server.free_disk_bytes.unwrap_or(0) / (1024 * 1024),
                server.template.as_deref().unwrap_or("none"),
            ))
        }
    }
}

#[derive(Debug, Subcommand)]
pub enum MailCommand {
    /// Send a test mail to an address, to see that the settings work.
    Test {
        /// Address that gets the test mail.
        address: String,
    },
}

/// Runs a command about mail and returns what to print.
pub async fn run_mail(config: &Config, command: MailCommand) -> Result<String> {
    match command {
        MailCommand::Test { address } => {
            let Some(smtp) = &config.smtp else {
                bail!(
                    "No mail server is set. Set {} and {} first; without them mails are only written to the terminal of the backend.",
                    crate::config::ENV_SMTP_HOST,
                    crate::config::ENV_MAIL_FROM
                );
            };
            let to = teachers::normalize_email(&address)
                .with_context(|| format!("{address} is not an address"))?;
            let mailer = Mailer::smtp(smtp)?;
            mailer.check().await.with_context(|| {
                format!("cannot talk to the mail server {}:{}", smtp.host, smtp.port)
            })?;
            mailer.send(mail::test(&to)).await?;
            Ok(format!(
                "The mail server {}:{} took a test mail for {to}, sent as {}.\nLook into the mailbox, also into the spam folder.",
                smtp.host, smtp.port, smtp.from
            ))
        }
    }
}

#[derive(Debug, Subcommand)]
pub enum TeacherCommand {
    /// List the teachers: their address, whether it is confirmed and in
    /// how many worlds they hold the privilege for web access.
    List,
}

/// Runs a command about teachers and returns what to print.
pub async fn run_teacher(pool: &SqlitePool, command: TeacherCommand) -> Result<String> {
    match command {
        TeacherCommand::List => {
            let list = teachers::list(pool).await?;
            if list.is_empty() {
                return Ok("There are no teachers yet.".to_owned());
            }
            let lines: Vec<String> = list
                .iter()
                .map(|teacher| {
                    let address = match (&teacher.email, &teacher.pending_email) {
                        (Some(email), Some(pending)) => {
                            format!("{email} (confirmed), {pending} (waiting)")
                        }
                        (Some(email), None) => format!("{email} (confirmed)"),
                        (None, Some(pending)) => format!("{pending} (waiting)"),
                        (None, None) => "no address".to_owned(),
                    };
                    let access = if teacher.worlds > 0 {
                        format!("privilege in {} world(s)", teacher.worlds)
                    } else {
                        "blocked, no world grants the privilege".to_owned()
                    };
                    format!("{}  {}  {}", teacher.account, address, access)
                })
                .collect();
            Ok(lines.join("\n"))
        }
    }
}

#[derive(Debug, Subcommand)]
pub enum WorldCommand {
    /// Create a world and print its key. The key is shown only now.
    Add { name: String },
    /// Give a world a new key and print it. The old key stops working.
    Rekey { name: String },
    /// List the worlds and when they were last heard of.
    List,
    /// Put a ping job in for a world, to check the way there and back.
    Ping { name: String },
    /// Show what the backend knows about a world: modules, progress,
    /// trophies and protocols.
    State { name: String },
    /// Ask a world to send its whole state again.
    Sync { name: String },
}

/// Runs a command that works on the database and returns what to print.
pub async fn run_world(pool: &SqlitePool, command: WorldCommand) -> Result<String> {
    match command {
        WorldCommand::Add { name } => {
            let (world, key) = worlds::add(pool, &name).await?;
            Ok(format!(
                "World '{}' created.\nid:  {}\nkey: {}\nThe key is shown only now. \
                 It belongs into the settings of the world, not into the repository.",
                world.name, world.id, key
            ))
        }
        WorldCommand::Rekey { name } => {
            let key = worlds::rekey(pool, &name).await?;
            Ok(format!(
                "New key for world '{}':\nkey: {}",
                name.trim(),
                key
            ))
        }
        WorldCommand::List => {
            let list = worlds::list(pool).await?;
            if list.is_empty() {
                return Ok("There are no worlds yet.".to_owned());
            }
            let now = crate::clock::now();
            let lines: Vec<String> = list
                .iter()
                .map(|world| {
                    let seen = match world.last_seen_at {
                        Some(time) => format!("last seen {} s ago", (now - time).max(0)),
                        None => "never seen".to_owned(),
                    };
                    let engine = world.engine.as_deref().unwrap_or("unknown engine");
                    format!("{}  {}  {}  {}", world.name, world.id, seen, engine)
                })
                .collect();
            Ok(lines.join("\n"))
        }
        WorldCommand::State { name } => {
            let Some(world) = worlds::find_by_name(pool, &name).await? else {
                bail!("there is no world called '{}'", name.trim());
            };
            Ok(format!(
                "World '{}'\n{}",
                world.name,
                state::describe(pool, &world.id).await?
            ))
        }
        WorldCommand::Sync { name } => {
            let Some(world) = worlds::find_by_name(pool, &name).await? else {
                bail!("there is no world called '{}'", name.trim());
            };
            let id = jobs::add(pool, &world.id, JOB_SYNC_STATE, &json!({})).await?;
            Ok(format!(
                "Sync job {id} is waiting for world '{}'. A world that is connected \
                 fetches it within 25 seconds and sends its whole state.",
                world.name
            ))
        }
        WorldCommand::Ping { name } => {
            let Some(world) = worlds::find_by_name(pool, &name).await? else {
                bail!("there is no world called '{}'", name.trim());
            };
            let id = jobs::add(pool, &world.id, JOB_PING, &json!({}))
                .await
                .context("cannot put the job in")?;
            Ok(format!(
                "Ping job {id} is waiting for world '{}'. A world that is connected \
                 fetches it within 25 seconds.",
                world.name
            ))
        }
    }
}

/// Returns the text of api/openapi.json.
pub fn openapi() -> String {
    app::openapi_json()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db;

    #[tokio::test]
    async fn gives_the_agent_a_key_and_shows_the_game_server() {
        let pool = db::open_in_memory().await.unwrap();
        let nothing = run_agent(&pool, AgentCommand::Show).await.unwrap();
        assert!(nothing.contains("no key"));

        let made = run_agent(&pool, AgentCommand::Key).await.unwrap();
        assert!(made.contains("key: lepa_"));
        let silent = run_agent(&pool, AgentCommand::Show).await.unwrap();
        assert!(silent.contains("never reported"));

        let report = lep_protocol::agent::AgentReport {
            version: "0.1.0".to_owned(),
            free_disk_bytes: 3 * 1024 * 1024,
            template: Some("bdbbf00c8a29".to_owned()),
        };
        game_server::note_report(&pool, &report).await.unwrap();
        let shown = run_agent(&pool, AgentCommand::Show).await.unwrap();
        assert!(shown.contains("connected"));
        assert!(shown.contains("agent version: 0.1.0"));
        assert!(shown.contains("free disk space: 3 MiB"));
        assert!(shown.contains("template for worlds: bdbbf00c8a29"));
    }

    #[tokio::test]
    async fn adds_lists_and_pings_worlds() {
        let pool = db::open_in_memory().await.unwrap();
        assert!(run_world(&pool, WorldCommand::List)
            .await
            .unwrap()
            .contains("no worlds"));

        let added = run_world(
            &pool,
            WorldCommand::Add {
                name: "7b".to_owned(),
            },
        )
        .await
        .unwrap();
        assert!(added.contains("key: lepw_"));

        let listed = run_world(&pool, WorldCommand::List).await.unwrap();
        assert!(listed.contains("7b") && listed.contains("never seen"));

        let pinged = run_world(
            &pool,
            WorldCommand::Ping {
                name: "7b".to_owned(),
            },
        )
        .await
        .unwrap();
        assert!(pinged.contains("is waiting"));
        let world = worlds::find_by_name(&pool, "7b").await.unwrap().unwrap();
        assert_eq!(jobs::take_waiting(&pool, &world.id).await.unwrap().len(), 1);

        let state = run_world(
            &pool,
            WorldCommand::State {
                name: "7b".to_owned(),
            },
        )
        .await
        .unwrap();
        assert!(state.contains("World '7b'") && state.contains("Modules: 0"));
        let sync = run_world(
            &pool,
            WorldCommand::Sync {
                name: "7b".to_owned(),
            },
        )
        .await
        .unwrap();
        assert!(sync.contains("is waiting"));
        assert!(run_world(
            &pool,
            WorldCommand::State {
                name: "8a".to_owned()
            }
        )
        .await
        .is_err());

        let rekeyed = run_world(
            &pool,
            WorldCommand::Rekey {
                name: "7b".to_owned(),
            },
        )
        .await
        .unwrap();
        assert!(rekeyed.contains("key: lepw_"));
    }

    #[tokio::test]
    async fn lists_teachers() {
        use lep_protocol::world::{WebAccessAction, WebAccessRequest};

        let pool = crate::db::open_in_memory().await.unwrap();
        assert!(run_teacher(&pool, TeacherCommand::List)
            .await
            .unwrap()
            .contains("no teachers"));

        let (world, _) = worlds::add(&pool, "7b").await.unwrap();
        teachers::set_holders(&pool, &world.id, &["lehrer1".to_owned()])
            .await
            .unwrap();
        let ask = |account: &str| WebAccessRequest {
            account: account.to_owned(),
            action: WebAccessAction::Set,
            email: Some(format!("{account}@schule.example")),
        };
        teachers::request(&pool, &ask("lehrer1"), 1000)
            .await
            .unwrap();
        teachers::request(&pool, &ask("lehrer2"), 1000)
            .await
            .unwrap();

        let listed = run_teacher(&pool, TeacherCommand::List).await.unwrap();
        let lines: Vec<&str> = listed.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("lehrer1@schule.example (waiting)"));
        assert!(lines[0].contains("privilege in 1 world(s)"));
        assert!(lines[1].contains("lehrer2"));
        assert!(lines[1].contains("blocked"));
    }

    #[tokio::test]
    async fn says_what_is_wrong() {
        let pool = db::open_in_memory().await.unwrap();
        assert!(run_world(
            &pool,
            WorldCommand::Ping {
                name: "7b".to_owned()
            }
        )
        .await
        .is_err());
        assert!(run_world(
            &pool,
            WorldCommand::Rekey {
                name: "7b".to_owned()
            }
        )
        .await
        .is_err());
        run_world(
            &pool,
            WorldCommand::Add {
                name: "7b".to_owned(),
            },
        )
        .await
        .unwrap();
        assert!(run_world(
            &pool,
            WorldCommand::Add {
                name: "7b".to_owned()
            }
        )
        .await
        .is_err());
    }
}
