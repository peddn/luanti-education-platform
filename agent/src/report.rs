//! What the agent says about the game server without being asked.

use std::path::Path;

use anyhow::{Context, Result};
use lep_protocol::agent::AgentReport;

/// Version of the agent, as in its package.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Describes the game server as it is now.
pub fn build(data_dir: &Path) -> Result<AgentReport> {
    Ok(AgentReport {
        version: VERSION.to_owned(),
        free_disk_bytes: free_disk_bytes(data_dir)?,
    })
}

/// Returns how much space is left for the agent on the disk that holds a
/// folder, in bytes.
pub fn free_disk_bytes(folder: &Path) -> Result<u64> {
    let disk = rustix::fs::statvfs(folder)
        .with_context(|| format!("cannot look at the disk of {}", folder.display()))?;
    // Counted in blocks that a user without special rights may fill.
    Ok(disk.f_bavail.saturating_mul(disk.f_frsize))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn describes_the_game_server() {
        let folder = tempfile::tempdir().unwrap();
        let report = build(folder.path()).unwrap();
        assert_eq!(report.version, VERSION);
        assert!(report.free_disk_bytes > 0);
    }

    #[test]
    fn a_missing_folder_is_an_error() {
        let folder = tempfile::tempdir().unwrap();
        assert!(build(&folder.path().join("missing")).is_err());
    }
}
