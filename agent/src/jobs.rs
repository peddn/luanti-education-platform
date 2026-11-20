//! The jobs the agent does for the backend. The list is fixed: a job of
//! a kind that is not named here is refused, and nothing from a job is
//! ever run as a command.

use lep_protocol::agent::{CreateWorld, JOB_CREATE_WORLD};
use lep_protocol::world::{Job, JobResult};

use crate::service::Agent;
use crate::worlds::{self, Created, Plan, WorldId};

/// Does a job and returns how it went. Doing the same job twice does no
/// harm: the backend hands a job out again until it has the result.
pub fn handle(agent: &Agent, job: &Job) -> JobResult {
    let outcome = match job.kind.as_str() {
        JOB_CREATE_WORLD => create_world(agent, job),
        _ => Err("the agent does not know this kind of job".to_owned()),
    };
    match outcome {
        Ok(message) => JobResult { ok: true, message },
        Err(message) => JobResult { ok: false, message },
    }
}

fn create_world(agent: &Agent, job: &Job) -> Result<String, String> {
    let wanted: CreateWorld = serde_json::from_value(job.payload.clone())
        .map_err(|_| "the job cannot be read".to_owned())?;
    let id = WorldId::parse(&wanted.world).map_err(|err| err.to_string())?;
    let Some(template) = &agent.template else {
        return Err("this agent has no template for worlds".to_owned());
    };
    let Some(admin) = agent.config.admin.as_deref() else {
        return Err("the settings of the agent name no admin for the worlds".to_owned());
    };
    let plan = Plan {
        data_dir: &agent.config.data_dir,
        template: &template.version,
        manifest: &template.manifest,
        ports: agent.config.ports.clone(),
        admin,
        backend: agent.config.backend.as_str().trim_end_matches('/'),
        bridge_key: &wanted.bridge_key,
    };
    match worlds::create(&id, &plan).map_err(|err| format!("{err:#}"))? {
        Created::New(note) => Ok(format!("created on port {}", note.port)),
        Created::Kept(note) => Ok(format!(
            "was there already on port {}, the key is written again",
            note.port
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::service::Prepared;
    use crate::worlds::testing::{manifest, ID};
    use serde_json::json;
    use std::path::Path;

    fn agent(folder: &Path, admin: bool, template: bool) -> Agent {
        let admin = if admin { "admin = \"peddn\"\n" } else { "" };
        let config = Config::parse(&format!(
            "backend = \"http://127.0.0.1:8080\"\nkey = \"lepa_0123\"\ndata_dir = \"{}\"\n{admin}",
            folder.display()
        ))
        .unwrap();
        Agent {
            config,
            template: template.then(|| Prepared {
                version: "bdbbf00c8a29".to_owned(),
                manifest: manifest(),
            }),
        }
    }

    fn job(kind: &str, payload: serde_json::Value) -> Job {
        Job {
            id: "j1".to_owned(),
            kind: kind.to_owned(),
            payload,
        }
    }

    fn create(key: &str) -> Job {
        job(JOB_CREATE_WORLD, json!({ "world": ID, "bridge_key": key }))
    }

    #[test]
    fn creates_a_world_once() {
        let folder = tempfile::tempdir().unwrap();
        let agent = agent(folder.path(), true, true);

        let first = handle(&agent, &create("lepw_0123"));
        assert!(first.ok, "{}", first.message);
        assert_eq!(first.message, "created on port 30000");
        let settings = folder.path().join("worlds").join(ID).join("minetest.conf");
        let text = std::fs::read_to_string(&settings).unwrap();
        assert!(text.contains("name = peddn\n"));
        assert!(text.contains("lep_bridge_url = http://127.0.0.1:8080\n"));

        // The same job again does no harm.
        let again = handle(&agent, &create("lepw_0123"));
        assert!(again.ok);
        assert!(again.message.contains("was there already on port 30000"));
        assert_eq!(worlds::list(folder.path()).unwrap().len(), 1);
    }

    #[test]
    fn refuses_what_it_cannot_do() {
        let folder = tempfile::tempdir().unwrap();

        let unknown = handle(&agent(folder.path(), true, true), &job("run", json!({})));
        assert!(!unknown.ok);
        assert!(unknown.message.contains("does not know"));

        let no_template = handle(&agent(folder.path(), true, false), &create("lepw_0123"));
        assert!(!no_template.ok);
        assert!(no_template.message.contains("no template"));

        let no_admin = handle(&agent(folder.path(), false, true), &create("lepw_0123"));
        assert!(!no_admin.ok);
        assert!(no_admin.message.contains("no admin"));

        let agent = agent(folder.path(), true, true);
        for payload in [
            json!({}),
            json!({ "world": "../../etc", "bridge_key": "lepw_0123" }),
            json!({ "world": ID, "bridge_key": "something" }),
            json!({ "world": ID }),
        ] {
            let refused = handle(&agent, &job(JOB_CREATE_WORLD, payload));
            assert!(!refused.ok);
        }
        assert!(worlds::list(folder.path()).unwrap().is_empty());
        assert!(!folder.path().join("worlds").join(ID).exists());
    }

    #[test]
    fn a_message_never_holds_the_key() {
        let folder = tempfile::tempdir().unwrap();
        let agent = agent(folder.path(), true, true);
        let wrong = handle(&agent, &create("lepw_secret key"));
        assert!(!wrong.ok);
        assert!(!wrong.message.contains("secret"));
        let good = handle(&agent, &create("lepw_secret"));
        assert!(good.ok);
        assert!(!good.message.contains("secret"));
    }
}
