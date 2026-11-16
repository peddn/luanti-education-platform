//! The time, as the database stores it.

use std::time::{SystemTime, UNIX_EPOCH};

/// Returns the seconds since 1970 (UTC).
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}
