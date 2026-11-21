//! What the agent does while it runs: it tells the backend regularly how
//! the game server is doing.

use std::future::Future;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::Result;
use lep_protocol::agent::REPORT_SECONDS;
use tokio::sync::{watch, Notify};

use crate::backend::{Backend, CallError};
use crate::config::Config;
use crate::template::{self, Manifest, Outcome, Template};
use crate::units::{self, Units};
use crate::{jobs, report};

/// The agent while it runs: its settings and its template.
pub struct Agent {
    pub config: Config,
    /// The unpacked template. Without it the agent runs and reports, but
    /// creates no worlds.
    pub template: Option<Prepared>,
    /// The services of the worlds.
    pub units: Arc<dyn Units>,
}

/// A template that lies unpacked in the folder of the agent.
pub struct Prepared {
    pub version: String,
    pub manifest: Manifest,
}

impl Agent {
    fn template_version(&self) -> Option<&str> {
        self.template
            .as_ref()
            .map(|template| template.version.as_str())
    }
}

/// Unpacks the template of this agent into its folder, if it has one.
/// An agent without a usable template still runs and reports, so the
/// returned text says what happened.
pub fn prepare_template(
    config: &Config,
    template: Option<Template<'_>>,
) -> (Option<Prepared>, String) {
    let Some(template) = template else {
        return (
            None,
            "this agent was built without a template for worlds and cannot create any. \
             scripts/agent-build.sh builds one with a template"
                .to_owned(),
        );
    };
    let unpacked = template::ensure(&config.data_dir, template).and_then(|(folder, outcome)| {
        let manifest = Manifest::read(&folder)?;
        Ok((folder, outcome, manifest))
    });
    match unpacked {
        Ok((folder, outcome, manifest)) => {
            let what = match outcome {
                Outcome::Present => "is in",
                Outcome::Unpacked => "unpacked into",
                Outcome::Repaired => "was damaged and is unpacked again into",
            };
            (
                Some(Prepared {
                    version: template.version.to_owned(),
                    manifest,
                }),
                format!("template {} {what} {}", template.version, folder.display()),
            )
        }
        Err(err) => (
            None,
            format!("the template {} cannot be used: {err:#}", template.version),
        ),
    }
}

/// Puts the template for the services of the worlds in place. The
/// returned text says what happened. If it fails, the agent still runs
/// and reports, but cannot start worlds.
pub fn prepare_units(config: &Config, units: &dyn Units) -> Result<String, String> {
    let text =
        units::template(&config.data_dir, &config.luanti).map_err(|err| format!("{err:#}"))?;
    match units.install(&text) {
        Ok(true) => Ok(format!("wrote {}", units::TEMPLATE_FILE)),
        Ok(false) => Ok(format!("{} is in place", units::TEMPLATE_FILE)),
        Err(err) => Err(format!(
            "cannot set up {}, so worlds cannot be started: {err:#}",
            units::TEMPLATE_FILE
        )),
    }
}

/// Puts the template for the services of the worlds in place, and
/// tries again until it worked: right after a boot the services of the
/// user may not be ready yet when the agent starts.
#[derive(Debug, Default)]
pub struct UnitsSetup {
    done: bool,
    said: Option<String>,
}

impl UnitsSetup {
    /// Tries once, unless it worked before. Returns what is worth a line
    /// in the log: success once, and every new reason for a failure.
    pub fn try_once(&mut self, agent: &Agent) -> Option<Result<String, String>> {
        if self.done {
            return None;
        }
        match prepare_units(&agent.config, &*agent.units) {
            Ok(said) => {
                self.done = true;
                Some(Ok(said))
            }
            Err(said) if self.said.as_deref() == Some(said.as_str()) => None,
            Err(said) => {
                self.said = Some(said.clone());
                Some(Err(said))
            }
        }
    }
}

/// Remembers how the last report went, so that the log says when
/// something changes and not the same thing every half minute.
#[derive(Debug, Default)]
pub struct Contact {
    last: Option<Result<(), CallError>>,
}

/// What is worth a line in the log after a report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum News {
    /// The first report got through.
    Connected,
    /// A report got through after one that did not.
    Back,
    /// A report did not get through, for another reason than the last.
    Lost(CallError),
}

impl Contact {
    /// Notes how a report went and returns what is new about it.
    pub fn note(&mut self, result: Result<(), CallError>) -> Option<News> {
        let news = match (&self.last, &result) {
            (None, Ok(())) => Some(News::Connected),
            (Some(Err(_)), Ok(())) => Some(News::Back),
            (Some(Ok(())), Ok(())) => None,
            (Some(Err(before)), Err(now)) if before == now => None,
            (_, Err(now)) => Some(News::Lost(now.clone())),
        };
        self.last = Some(result);
        news
    }
}

/// Sends one report and returns how it went.
pub async fn report_once(agent: &Agent, backend: &Backend) -> Result<(), CallError> {
    // Without systemd no world runs, and the jobs say why.
    let running = agent.units.running().unwrap_or_default();
    let report = report::build(
        &agent.config.data_dir,
        agent.template_version(),
        &running,
        agent.config.host.as_deref(),
    )
    .map_err(|err| CallError::Unreachable(format!("nothing to report: {err:#}")))?;
    backend.send_report(&report).await
}

/// How long the agent waits between its steps.
#[derive(Debug, Clone, Copy)]
pub struct Timing {
    /// Time between two reports.
    pub report: Duration,
    /// How long a request for jobs may stay open at the backend.
    pub job_wait: Duration,
    /// Pause after a request for jobs that failed.
    pub retry: Duration,
}

impl Default for Timing {
    fn default() -> Self {
        Self {
            report: Duration::from_secs(REPORT_SECONDS),
            job_wait: Duration::from_secs(25),
            retry: Duration::from_secs(10),
        }
    }
}

/// Runs until `stop` is done: reports regularly and does the jobs the
/// backend has. A backend that is out of reach is no reason to end: the
/// agent tries again.
pub async fn run(agent: &Agent, backend: &Backend, stop: impl Future<Output = ()>) {
    run_with(agent, backend, Timing::default(), stop).await;
}

/// Like `run`, with chosen times.
pub async fn run_with(
    agent: &Agent,
    backend: &Backend,
    timing: Timing,
    stop: impl Future<Output = ()>,
) {
    let (stopping, stopped) = watch::channel(false);
    // Rung after a job, so the backend hears at once what changed.
    let report_now = Notify::new();
    tokio::join!(
        report_loop(agent, backend, timing, &report_now, stopped.clone()),
        job_loop(agent, backend, timing, &report_now, stopped),
        async {
            stop.await;
            let _ = stopping.send(true);
        }
    );
}

async fn until_stopped(stopped: &mut watch::Receiver<bool>) {
    // An error means nobody can stop the agent any more, which only
    // happens when it ends anyway.
    let _ = stopped.wait_for(|stopped| *stopped).await;
}

async fn report_loop(
    agent: &Agent,
    backend: &Backend,
    timing: Timing,
    report_now: &Notify,
    mut stopped: watch::Receiver<bool>,
) {
    let mut contact = Contact::default();
    let mut units = UnitsSetup::default();
    loop {
        match units.try_once(agent) {
            Some(Ok(said)) => tracing::info!("{said}"),
            Some(Err(said)) => tracing::warn!("{said}. Trying again with every report"),
            None => {}
        }
        match contact.note(report_once(agent, backend).await) {
            Some(News::Connected) => tracing::info!("connected to the backend"),
            Some(News::Back) => tracing::info!("the backend is back"),
            Some(News::Lost(why)) => {
                tracing::warn!("{why}. Trying again every {:?}", timing.report)
            }
            None => {}
        }
        tokio::select! {
            () = until_stopped(&mut stopped) => return,
            () = tokio::time::sleep(timing.report) => {}
            () = report_now.notified() => {}
        }
    }
}

async fn job_loop(
    agent: &Agent,
    backend: &Backend,
    timing: Timing,
    report_now: &Notify,
    mut stopped: watch::Receiver<bool>,
) {
    loop {
        let asked = Instant::now();
        let fetched = tokio::select! {
            () = until_stopped(&mut stopped) => return,
            fetched = backend.fetch_jobs(timing.job_wait) => fetched,
        };
        // Why the backend cannot be reached is said by the reports.
        let jobs = fetched.unwrap_or_default();
        for job in &jobs {
            let result = jobs::handle(agent, job);
            if result.ok {
                tracing::info!("job {}: {}", job.kind, result.message);
            } else {
                tracing::warn!("job {} refused: {}", job.kind, result.message);
            }
            // If the result does not get through, the job comes again
            // and is answered again.
            let _ = backend.send_result(&job.id, &result).await;
        }
        if !jobs.is_empty() {
            report_now.notify_one();
        }
        // An answer without jobs that came at once must not turn this
        // into a busy loop, whatever the reason.
        if jobs.is_empty() && asked.elapsed() < timing.retry.min(timing.job_wait) {
            tokio::select! {
                () = until_stopped(&mut stopped) => return,
                () = tokio::time::sleep(timing.retry) => {}
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_changes_are_news() {
        let mut contact = Contact::default();
        assert_eq!(contact.note(Ok(())), Some(News::Connected));
        assert_eq!(contact.note(Ok(())), None);

        let gone = CallError::Unreachable("no connection".to_owned());
        assert_eq!(
            contact.note(Err(gone.clone())),
            Some(News::Lost(gone.clone()))
        );
        assert_eq!(contact.note(Err(gone)), None);
        // Another reason is said again.
        assert_eq!(
            contact.note(Err(CallError::Refused)),
            Some(News::Lost(CallError::Refused))
        );
        assert_eq!(contact.note(Ok(())), Some(News::Back));
    }

    #[test]
    fn prepares_the_template_or_says_why_not() {
        use crate::template::testing::{pack, SMALL};
        let folder = tempfile::tempdir().unwrap();
        let config = Config::parse(&format!(
            "backend = \"http://127.0.0.1:1\"\nkey = \"lepa_0123\"\ndata_dir = \"{}\"\n",
            folder.path().display()
        ))
        .unwrap();

        let (prepared, text) = prepare_template(&config, None);
        assert!(prepared.is_none());
        assert!(text.contains("without a template"));

        let (packed, archive) = pack(SMALL);
        let template = Template {
            version: &packed,
            archive: &archive,
        };
        let (prepared, text) = prepare_template(&config, Some(template));
        let prepared = prepared.unwrap();
        assert_eq!(prepared.version, packed);
        assert_eq!(prepared.manifest.lep_mods, ["lep_core"]);
        assert!(text.contains("unpacked into"), "{text}");
        let (_, text) = prepare_template(&config, Some(template));
        assert!(text.contains("is in"), "{text}");

        let broken = Template {
            version: &packed,
            archive: b"no archive",
        };
        std::fs::remove_dir_all(folder.path().join("templates")).unwrap();
        let (prepared, text) = prepare_template(&config, Some(broken));
        assert!(prepared.is_none());
        assert!(text.contains("cannot be used"), "{text}");
    }

    #[test]
    fn puts_the_service_of_the_worlds_in_place() {
        use crate::units::testing::FakeUnits;
        let config = Config::parse(
            "backend = \"http://127.0.0.1:1\"\nkey = \"lepa_0123\"\ndata_dir = \"/var/lib/lep\"\n",
        )
        .unwrap();
        let units = FakeUnits::default();
        assert!(prepare_units(&config, &units).unwrap().contains("wrote"));
        assert!(prepare_units(&config, &units).unwrap().contains("in place"));
        let text = units.template.lock().unwrap().clone().unwrap();
        assert!(text.contains("ExecStart=/usr/local/bin/luantiserver --quiet"));
        assert!(text.contains("/var/lib/lep/worlds/%i/world"));

        let refused = prepare_units(&config, &FakeUnits::broken()).unwrap_err();
        assert!(refused.contains("worlds cannot be started"));

        let odd = Config::parse(
            "backend = \"http://127.0.0.1:1\"\nkey = \"lepa_0123\"\ndata_dir = \"/var/lib/my lep\"\n",
        )
        .unwrap();
        assert!(prepare_units(&odd, &units).is_err());
    }

    #[test]
    fn tries_the_service_of_the_worlds_until_it_is_in_place() {
        use crate::units::testing::FakeUnits;
        let config = Config::parse(
            "backend = \"http://127.0.0.1:1\"\nkey = \"lepa_0123\"\ndata_dir = \"/var/lib/lep\"\n",
        )
        .unwrap();
        let units = Arc::new(FakeUnits::default());
        *units.install_failures.lock().unwrap() = 2;
        let agent = Agent {
            config,
            template: None,
            units: units.clone(),
        };

        let mut setup = UnitsSetup::default();
        // The reason is said once, not with every attempt.
        assert!(matches!(setup.try_once(&agent), Some(Err(_))));
        assert_eq!(setup.try_once(&agent), None);
        // Then systemd is ready.
        assert!(matches!(setup.try_once(&agent), Some(Ok(_))));
        assert!(units.template.lock().unwrap().is_some());
        // Once it is in place, nothing is tried any more.
        assert_eq!(setup.try_once(&agent), None);
        assert_eq!(units.calls(), ["install"]);
    }

    #[test]
    fn a_failed_start_is_news_too() {
        let mut contact = Contact::default();
        assert_eq!(
            contact.note(Err(CallError::Refused)),
            Some(News::Lost(CallError::Refused))
        );
        assert_eq!(contact.note(Ok(())), Some(News::Back));
    }
}
