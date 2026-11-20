//! The jobs the agent does for the backend. The list is fixed: a job of
//! a kind that is not named here is refused, and nothing from a job is
//! ever run as a command.

use lep_protocol::agent::{
    CreateWorld, WorldJob, JOB_CREATE_WORLD, JOB_RESTART_WORLD, JOB_START_WORLD, JOB_STOP_WORLD,
};
use lep_protocol::world::{Job, JobResult};

use crate::service::Agent;
use crate::worlds::{self, Created, Plan, WorldId};

/// Does a job and returns how it went. Doing the same job twice does no
/// harm: the backend hands a job out again until it has the result.
pub fn handle(agent: &Agent, job: &Job) -> JobResult {
    let outcome = match job.kind.as_str() {
        JOB_CREATE_WORLD => create_world(agent, job),
        JOB_START_WORLD => steer(agent, job, Step::Start),
        JOB_STOP_WORLD => steer(agent, job, Step::Stop),
        JOB_RESTART_WORLD => steer(agent, job, Step::Restart),
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
        ipv6: worlds::machine_has_ipv6(),
    };
    // A world starts as soon as it is there. One that was there and
    // runs is started anew, so it reads its new key.
    let (said, was_there) = match worlds::create(&id, &plan).map_err(|err| format!("{err:#}"))? {
        Created::New(note) => (format!("created on port {}", note.port), false),
        Created::Kept(note) => (
            format!(
                "was there already on port {}, the key is written again",
                note.port
            ),
            true,
        ),
    };
    let started = if was_there {
        agent
            .units
            .restart(&id)
            .and_then(|()| agent.units.start(&id))
    } else {
        agent.units.start(&id)
    };
    match started {
        Ok(()) => Ok(format!("{said}, and it runs")),
        Err(err) => Err(format!("{said}, but it could not be started: {err:#}")),
    }
}

enum Step {
    Start,
    Stop,
    Restart,
}

/// Starts or stops the service of a world the agent has.
fn steer(agent: &Agent, job: &Job, step: Step) -> Result<String, String> {
    let wanted: WorldJob = serde_json::from_value(job.payload.clone())
        .map_err(|_| "the job cannot be read".to_owned())?;
    let id = WorldId::parse(&wanted.world).map_err(|err| err.to_string())?;
    if !worlds::exists(&agent.config.data_dir, &id) {
        return Err("the agent has no such world".to_owned());
    }
    let (done, said) = match step {
        Step::Start => (agent.units.start(&id), "started"),
        Step::Stop => (agent.units.stop(&id), "stopped"),
        Step::Restart => (agent.units.restart(&id), "started anew if it ran"),
    };
    done.map(|()| said.to_owned())
        .map_err(|err| format!("{err:#}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::service::Prepared;
    use crate::units::testing::FakeUnits;
    use crate::worlds::testing::{manifest, ID, OTHER};
    use serde_json::json;
    use std::path::Path;
    use std::sync::Arc;

    fn agent(folder: &Path, admin: bool, template: bool) -> (Agent, Arc<FakeUnits>) {
        agent_with(folder, admin, template, FakeUnits::default())
    }

    /// Returns the agent and the stand-in for systemd it uses, to see
    /// what was asked of it.
    fn agent_with(
        folder: &Path,
        admin: bool,
        template: bool,
        units: FakeUnits,
    ) -> (Agent, Arc<FakeUnits>) {
        let admin = if admin { "admin = \"peddn\"\n" } else { "" };
        let config = Config::parse(&format!(
            "backend = \"http://127.0.0.1:8080\"\nkey = \"lepa_0123\"\ndata_dir = \"{}\"\n{admin}",
            folder.display()
        ))
        .unwrap();
        let units = Arc::new(units);
        let agent = Agent {
            config,
            template: template.then(|| Prepared {
                version: "bdbbf00c8a29".to_owned(),
                manifest: manifest(),
            }),
            units: units.clone(),
        };
        (agent, units)
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

    fn about(kind: &str, world: &str) -> Job {
        job(kind, json!({ "world": world }))
    }

    #[test]
    fn creates_a_world_once_and_starts_it() {
        let folder = tempfile::tempdir().unwrap();
        let (agent, units) = agent(folder.path(), true, true);

        let first = handle(&agent, &create("lepw_0123"));
        assert!(first.ok, "{}", first.message);
        assert_eq!(first.message, "created on port 30000, and it runs");
        let settings = folder.path().join("worlds").join(ID).join("minetest.conf");
        let text = std::fs::read_to_string(&settings).unwrap();
        assert!(text.contains("name = peddn\n"));
        assert!(text.contains("lep_bridge_url = http://127.0.0.1:8080\n"));
        assert_eq!(units.calls(), [format!("start {ID}")]);

        // The same job again does no harm. The world is started anew, so
        // it reads the key that was written again.
        let again = handle(&agent, &create("lepw_0123"));
        assert!(again.ok);
        assert!(again.message.contains("was there already on port 30000"));
        assert_eq!(worlds::list(folder.path()).unwrap().len(), 1);
        assert_eq!(
            units.calls()[1..],
            [format!("restart {ID}"), format!("start {ID}")]
        );
    }

    #[test]
    fn a_world_that_cannot_be_started_is_still_there() {
        let folder = tempfile::tempdir().unwrap();
        let (agent, _) = agent_with(folder.path(), true, true, FakeUnits::broken());
        let result = handle(&agent, &create("lepw_0123"));
        assert!(!result.ok);
        assert!(
            result
                .message
                .starts_with("created on port 30000, but it could not be started"),
            "{}",
            result.message
        );
        assert_eq!(worlds::list(folder.path()).unwrap().len(), 1);
    }

    #[test]
    fn starts_and_stops_the_worlds_it_has() {
        let folder = tempfile::tempdir().unwrap();
        let (agent, units) = agent(folder.path(), true, true);
        assert!(handle(&agent, &create("lepw_0123")).ok);
        let id = WorldId::parse(ID).unwrap();

        let stopped = handle(&agent, &about(JOB_STOP_WORLD, ID));
        assert!(stopped.ok);
        assert_eq!(stopped.message, "stopped");
        assert!(!units.running.lock().unwrap().contains(&id));

        let started = handle(&agent, &about(JOB_START_WORLD, ID));
        assert!(started.ok);
        assert!(units.running.lock().unwrap().contains(&id));
        // Twice is as good as once.
        assert!(handle(&agent, &about(JOB_START_WORLD, ID)).ok);

        assert!(handle(&agent, &about(JOB_RESTART_WORLD, ID)).ok);
        assert_eq!(
            units.calls()[1..],
            [
                format!("stop {ID}"),
                format!("start {ID}"),
                format!("start {ID}"),
                format!("restart {ID}")
            ]
        );
    }

    #[test]
    fn steers_no_service_of_a_world_it_does_not_have() {
        let folder = tempfile::tempdir().unwrap();
        let (agent, units) = agent(folder.path(), true, true);
        for kind in [JOB_START_WORLD, JOB_STOP_WORLD, JOB_RESTART_WORLD] {
            for world in [OTHER, "../../etc", "lep-agent", ""] {
                let refused = handle(&agent, &about(kind, world));
                assert!(!refused.ok, "{kind} {world}");
            }
            assert!(!handle(&agent, &job(kind, json!({}))).ok);
        }
        // systemd was never asked.
        assert!(units.calls().is_empty());
    }

    #[test]
    fn says_why_systemd_did_not_do_it() {
        let folder = tempfile::tempdir().unwrap();
        let (working, _) = agent(folder.path(), true, true);
        assert!(handle(&working, &create("lepw_0123")).ok);
        let (broken, _) = agent_with(folder.path(), true, true, FakeUnits::broken());
        let refused = handle(&broken, &about(JOB_START_WORLD, ID));
        assert!(!refused.ok);
        assert!(refused.message.contains("no systemd here"));
    }

    #[test]
    fn refuses_what_it_cannot_do() {
        let folder = tempfile::tempdir().unwrap();

        let (with_all, units) = agent(folder.path(), true, true);
        let unknown = handle(&with_all, &job("run", json!({})));
        assert!(!unknown.ok);
        assert!(unknown.message.contains("does not know"));

        let (no_template, _) = agent(folder.path(), true, false);
        let refused = handle(&no_template, &create("lepw_0123"));
        assert!(!refused.ok);
        assert!(refused.message.contains("no template"));

        let (no_admin, _) = agent(folder.path(), false, true);
        let refused = handle(&no_admin, &create("lepw_0123"));
        assert!(!refused.ok);
        assert!(refused.message.contains("no admin"));

        for payload in [
            json!({}),
            json!({ "world": "../../etc", "bridge_key": "lepw_0123" }),
            json!({ "world": ID, "bridge_key": "something" }),
            json!({ "world": ID }),
        ] {
            let refused = handle(&with_all, &job(JOB_CREATE_WORLD, payload));
            assert!(!refused.ok);
        }
        assert!(worlds::list(folder.path()).unwrap().is_empty());
        assert!(!folder.path().join("worlds").join(ID).exists());
        assert!(units.calls().is_empty());
    }

    #[test]
    fn a_message_never_holds_the_key() {
        let folder = tempfile::tempdir().unwrap();
        let (agent, _) = agent(folder.path(), true, true);
        let wrong = handle(&agent, &create("lepw_secret key"));
        assert!(!wrong.ok);
        assert!(!wrong.message.contains("secret"));
        let good = handle(&agent, &create("lepw_secret"));
        assert!(good.ok);
        assert!(!good.message.contains("secret"));
    }
}
