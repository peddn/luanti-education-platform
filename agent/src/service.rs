//! What the agent does while it runs: it tells the backend regularly how
//! the game server is doing.

use std::future::Future;
use std::time::Duration;

use anyhow::Result;
use lep_protocol::agent::REPORT_SECONDS;

use crate::backend::{Backend, CallError};
use crate::config::Config;
use crate::report;

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
pub async fn report_once(config: &Config, backend: &Backend) -> Result<(), CallError> {
    let report = report::build(&config.data_dir)
        .map_err(|err| CallError::Unreachable(format!("nothing to report: {err:#}")))?;
    backend.send_report(&report).await
}

/// Runs until `stop` is done. A backend that is out of reach is no
/// reason to end: the agent tries again.
pub async fn run(config: &Config, backend: &Backend, stop: impl Future<Output = ()>) {
    run_every(config, backend, Duration::from_secs(REPORT_SECONDS), stop).await;
}

/// Like `run`, with a chosen time between two reports.
pub async fn run_every(
    config: &Config,
    backend: &Backend,
    pause: Duration,
    stop: impl Future<Output = ()>,
) {
    let mut contact = Contact::default();
    tokio::pin!(stop);
    loop {
        match contact.note(report_once(config, backend).await) {
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
    fn a_failed_start_is_news_too() {
        let mut contact = Contact::default();
        assert_eq!(
            contact.note(Err(CallError::Refused)),
            Some(News::Lost(CallError::Refused))
        );
        assert_eq!(contact.note(Ok(())), Some(News::Back));
    }
}
