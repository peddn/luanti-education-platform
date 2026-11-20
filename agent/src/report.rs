//! What the agent says about the game server without being asked.

use std::path::Path;

use anyhow::{Context, Result};
use lep_protocol::agent::AgentReport;

use crate::worlds;

/// Version of the agent, as in its package.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Describes the game server as it is now.
pub fn build(data_dir: &Path, template: Option<&str>) -> Result<AgentReport> {
    Ok(AgentReport {
        version: VERSION.to_owned(),
        free_disk_bytes: free_disk_bytes(data_dir)?,
        template: template.map(str::to_owned),
        worlds: worlds::states(data_dir)?,
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
        let report = build(folder.path(), Some("bdbbf00c8a29")).unwrap();
        assert_eq!(report.version, VERSION);
        assert_eq!(report.template.as_deref(), Some("bdbbf00c8a29"));
        assert_eq!(build(folder.path(), None).unwrap().template, None);
        assert!(report.worlds.is_empty());
        assert!(report.free_disk_bytes > 0);
    }

    #[test]
    fn a_missing_folder_is_an_error() {
        let folder = tempfile::tempdir().unwrap();
        assert!(build(&folder.path().join("missing"), None).is_err());
    }
}
