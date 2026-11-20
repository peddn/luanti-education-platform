-- The game server and its agent. There is exactly one game server for
-- all worlds, so this table holds at most one row.
CREATE TABLE game_server (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    -- Hash of the key the agent calls with. The key itself is shown once
    -- when it is made and never stored.
    key_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    -- What the agent last said, with the time in seconds since 1970.
    -- NULL as long as it never reported.
    last_seen_at INTEGER,
    version TEXT,
    free_disk_bytes INTEGER
) STRICT;
