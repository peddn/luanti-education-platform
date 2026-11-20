//! The way to the backend. The agent calls, the backend answers.

use std::fmt;
use std::time::Duration;

use anyhow::{Context, Result};
use lep_protocol::agent::AgentReport;
use lep_protocol::world::{Job, JobList, JobResult};
use reqwest::{redirect, Client, StatusCode, Url};

use crate::config::Config;

/// Longest time one request may take.
const TIMEOUT: Duration = Duration::from_secs(20);

/// Why a request did not get through. The texts say nothing about the
/// key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CallError {
    /// The backend does not know the key.
    Refused,
    /// The backend did not answer.
    Unreachable(String),
    /// The backend answered, but not with what the agent expects.
    Failed(u16),
}

impl fmt::Display for CallError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Refused => write!(
                f,
                "the backend refuses the key. A new one comes from: lep-backend agent key"
            ),
            Self::Unreachable(why) => write!(f, "the backend cannot be reached: {why}"),
            Self::Failed(status) => write!(f, "the backend answered with status {status}"),
        }
    }
}

impl std::error::Error for CallError {}

/// The backend, as the agent reaches it.
pub struct Backend {
    http: Client,
    report: Url,
    jobs: Url,
    key: String,
}

impl Backend {
    pub fn new(config: &Config) -> Result<Self> {
        // One way of doing TLS for the whole program. A second call
        // changes nothing.
        let _ = rustls::crypto::ring::default_provider().install_default();
        let http = Client::builder()
            .timeout(TIMEOUT)
            // The key must not follow a redirect to another place.
            .redirect(redirect::Policy::none())
            .user_agent(concat!("lep-agent/", env!("CARGO_PKG_VERSION")))
            .build()
            .context(
                "cannot set up the connection to the backend. The certificates of the \
                 system must be there (package ca-certificates) and readable",
            )?;
        Ok(Self {
            http,
            report: config
                .backend
                .join("api/agent/v1/report")
                .context("the address of the backend cannot be used")?,
            jobs: config
                .backend
                .join("api/agent/v1/jobs")
                .context("the address of the backend cannot be used")?,
            key: config.key.clone(),
        })
    }

    /// Tells the backend how the game server is doing.
    pub async fn send_report(&self, report: &AgentReport) -> Result<(), CallError> {
        let response = self
            .http
            .post(self.report.clone())
            .bearer_auth(&self.key)
            .json(report)
            .send()
            .await
            .map_err(|err| CallError::Unreachable(reason(&err)))?;
        match response.status() {
            StatusCode::OK => Ok(()),
            StatusCode::UNAUTHORIZED => Err(CallError::Refused),
            other => Err(CallError::Failed(other.as_u16())),
        }
    }
}

impl Backend {
    /// Asks for the jobs that wait for the agent. If there are none, the
    /// backend keeps the request open for up to `wait` and answers as
    /// soon as one comes.
    pub async fn fetch_jobs(&self, wait: Duration) -> Result<Vec<Job>, CallError> {
        let mut url = self.jobs.clone();
        url.query_pairs_mut()
            .append_pair("wait", &wait.as_secs().to_string());
        let response = self
            .http
            .get(url)
            // Longer than the backend waits, so its answer still arrives.
            .timeout(wait + TIMEOUT)
            .bearer_auth(&self.key)
            .send()
            .await
            .map_err(|err| CallError::Unreachable(reason(&err)))?;
        match response.status() {
            StatusCode::OK => {}
            StatusCode::UNAUTHORIZED => return Err(CallError::Refused),
            other => return Err(CallError::Failed(other.as_u16())),
        }
        let list: JobList = response
            .json()
            .await
            .map_err(|_| CallError::Unreachable("the answer cannot be read".to_owned()))?;
        Ok(list.jobs)
    }

    /// Tells the backend how a job went.
    pub async fn send_result(&self, job_id: &str, result: &JobResult) -> Result<(), CallError> {
        // The id becomes part of the address, so it must be a plain name.
        if job_id.is_empty()
            || !job_id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-')
        {
            return Err(CallError::Unreachable(
                "the id of the job cannot be used".to_owned(),
            ));
        }
        let mut url = self.jobs.clone();
        url.set_path(&format!("{}/{job_id}/result", self.jobs.path()));
        let response = self
            .http
            .post(url)
            .bearer_auth(&self.key)
            .json(result)
            .send()
            .await
            .map_err(|err| CallError::Unreachable(reason(&err)))?;
        match response.status() {
            StatusCode::OK => Ok(()),
            StatusCode::UNAUTHORIZED => Err(CallError::Refused),
            other => Err(CallError::Failed(other.as_u16())),
        }
    }
}

/// Says in a few words why a request failed, without the address: the
/// message of the library repeats it for every failure.
fn reason(err: &reqwest::Error) -> String {
    if err.is_timeout() {
        "no answer in time".to_owned()
    } else if err.is_connect() {
        "no connection".to_owned()
    } else {
        "the request failed".to_owned()
    }
}
