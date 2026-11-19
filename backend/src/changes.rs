//! Tells open pages in browsers that something about a group changed.
//!
//! A page keeps a request open and gets a short signal: which part of
//! the group changed, never the data itself. It then loads that part
//! again, through the ways it always uses, with the rights it always
//! needs. The signals are not kept: a page that was away loads
//! everything again when it is back.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use lep_protocol::web::ChangeTopic;
use tokio::sync::{broadcast, watch};

/// How many signals a page that reads slowly may fall behind before it
/// is told to load everything again.
const BACKLOG: usize = 64;

/// All parts of a group a page can show.
pub const ALL: [ChangeTopic; 3] = [
    ChangeTopic::Group,
    ChangeTopic::Students,
    ChangeTopic::Progress,
];

/// The signals of all groups, and the one that says the backend stops.
#[derive(Clone)]
pub struct Changes {
    by_group: Arc<Mutex<HashMap<String, broadcast::Sender<ChangeTopic>>>>,
    stopping: watch::Sender<bool>,
}

impl Default for Changes {
    fn default() -> Self {
        Self {
            by_group: Arc::default(),
            stopping: watch::channel(false).0,
        }
    }
}

impl Changes {
    fn sender(&self, group_id: &str) -> broadcast::Sender<ChangeTopic> {
        let mut by_group = self.by_group.lock().expect("the list of signals is broken");
        by_group
            .entry(group_id.to_owned())
            .or_insert_with(|| broadcast::channel(BACKLOG).0)
            .clone()
    }

    /// Returns the signals of a group from now on.
    pub fn listen(&self, group_id: &str) -> broadcast::Receiver<ChangeTopic> {
        self.sender(group_id).subscribe()
    }

    /// Says that parts of a group changed. Nobody listening is fine.
    pub fn tell(&self, group_id: &str, topics: &[ChangeTopic]) {
        let sender = self.sender(group_id);
        for topic in topics {
            let _ = sender.send(*topic);
        }
    }

    /// Says that the backend stops: every open request ends.
    pub fn stop(&self) {
        self.stopping.send_replace(true);
    }

    /// Returns a future that resolves when the backend stops.
    pub fn stopped(&self) -> impl std::future::Future<Output = ()> + Send + 'static {
        let mut stopping = self.stopping.subscribe();
        async move {
            // An error means the sender is gone: the backend is stopping.
            let _ = stopping.wait_for(|stopping| *stopping).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn tells_only_the_listeners_of_the_group() {
        let changes = Changes::default();
        let mut first = changes.listen("7b");
        let mut other = changes.listen("8a");
        // Nobody listening yet is no error.
        changes.tell("9c", &ALL);
        changes.tell("7b", &[ChangeTopic::Progress, ChangeTopic::Students]);
        assert_eq!(first.recv().await.unwrap(), ChangeTopic::Progress);
        assert_eq!(first.recv().await.unwrap(), ChangeTopic::Students);
        assert!(other.try_recv().is_err());
        // Signals are not kept for who listens later.
        assert!(changes.listen("7b").try_recv().is_err());
    }

    #[tokio::test]
    async fn says_when_the_backend_stops() {
        let changes = Changes::default();
        let stopped = changes.stopped();
        tokio::pin!(stopped);
        assert!(
            tokio::time::timeout(Duration::from_millis(20), &mut stopped)
                .await
                .is_err()
        );
        changes.stop();
        tokio::time::timeout(Duration::from_secs(1), &mut stopped)
            .await
            .unwrap();
        // Who asks afterwards is told at once.
        tokio::time::timeout(Duration::from_secs(1), changes.stopped())
            .await
            .unwrap();
    }
}
