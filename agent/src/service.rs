//! What the agent does while it runs: it tells the backend regularly how
//! the game server is doing.

use std::future::Future;
use std::time::Duration;

use anyhow::Result;
use lep_protocol::agent::REPORT_SECONDS;

use crate::backend::{Backend, CallError};
use crate::config::Config;
use crate::report;
use crate::template::{self, Outcome, Template};

/// Unpacks the template of this agent into its folder, if it has one,
/// and returns its version. An agent without a usable template still
/// runs and reports, so the returned text says what happened.
pub fn prepare_template(
    config: &Config,
    template: Option<Template<'_>>,
) -> (Option<String>, String) {
    let Some(template) = template else {
        return (
            None,
            "this agent was built without a template for worlds and cannot create any. \
             scripts/agent-build.sh builds one with a template"
                .to_owned(),
        );
    };
    match template::ensure(&config.data_dir, template) {
        Ok((folder, outcome)) => {
            let what = match outcome {
                Outcome::Present => "is in",
                Outcome::Unpacked => "unpacked into",
                Outcome::Repaired => "was damaged and is unpacked again into",
            };
            (
                Some(template.version.to_owned()),
                format!("template {} {what} {}", template.version, folder.display()),
            )
        }
        Err(err) => (
            None,
            format!("the template {} cannot be used: {err:#}", template.version),
        ),
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
pub async fn report_once(
    config: &Config,
    backend: &Backend,
    template: Option<&str>,
) -> Result<(), CallError> {
    let report = report::build(&config.data_dir, template)
        .map_err(|err| CallError::Unreachable(format!("nothing to report: {err:#}")))?;
    backend.send_report(&report).await
}

/// Runs until `stop` is done. A backend that is out of reach is no
/// reason to end: the agent tries again.
pub async fn run(
    config: &Config,
    backend: &Backend,
    template: Option<&str>,
    stop: impl Future<Output = ()>,
) {
    let pause = Duration::from_secs(REPORT_SECONDS);
    run_every(config, backend, template, pause, stop).await;
}

/// Like `run`, with a chosen time between two reports.
pub async fn run_every(
    config: &Config,
    backend: &Backend,
    template: Option<&str>,
    pause: Duration,
    stop: impl Future<Output = ()>,
) {
    let mut contact = Contact::default();
    tokio::pin!(stop);
    loop {
        match contact.note(report_once(config, backend, template).await) {
            Some(News::Connected) => tracing::info!("connected to the backend"),
            Some(News::Back) => tracing::info!("the backend is back"),
            Some(News::Lost(why)) => tracing::warn!("{why}. Trying again every {pause:?}"),
            None => {}
        }
        tokio::select! {
            () = &mut stop => return,
            () = tokio::time::sleep(pause) => {}
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

        let (version, text) = prepare_template(&config, None);
        assert_eq!(version, None);
        assert!(text.contains("without a template"));

        let (packed, archive) = pack(SMALL);
        let template = Template {
            version: &packed,
            archive: &archive,
        };
        let (version, text) = prepare_template(&config, Some(template));
        assert_eq!(version.as_deref(), Some(packed.as_str()));
        assert!(text.contains("unpacked into"), "{text}");
        let (_, text) = prepare_template(&config, Some(template));
        assert!(text.contains("is in"), "{text}");

        let broken = Template {
            version: &packed,
            archive: b"no archive",
        };
        std::fs::remove_dir_all(folder.path().join("templates")).unwrap();
        let (version, text) = prepare_template(&config, Some(broken));
        assert_eq!(version, None);
        assert!(text.contains("cannot be used"), "{text}");
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
