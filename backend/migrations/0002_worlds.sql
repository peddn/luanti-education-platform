-- Worlds, the events they send and the jobs that wait for them.

-- A world is one Luanti world, the home of one group. Times are seconds
-- since 1970 (UTC).
CREATE TABLE worlds (
    -- Fixed internal identifier. It never changes.
    id TEXT PRIMARY KEY,
    -- Name for people. It can be changed.
    name TEXT NOT NULL UNIQUE,
    -- SHA-256 of the key the world calls with. The key itself is shown
    -- once and never stored.
    key_hash TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    -- Last request of the world, of any kind.
    last_seen_at INTEGER,
    -- What the world said about itself when it last started.
    started_at INTEGER,
    engine TEXT,
    -- Names of the loaded mods as a JSON list.
    mods TEXT
) STRICT;

-- Ids of the events that were taken in, so an event that arrives twice is
-- handled once.
CREATE TABLE world_events (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    event_id TEXT NOT NULL,
    received_at INTEGER NOT NULL,
    PRIMARY KEY (world_id, event_id)
) STRICT, WITHOUT ROWID;

-- Jobs for the worlds. A job waits until the world reports its result.
CREATE TABLE jobs (
    id TEXT PRIMARY KEY,
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    -- Details as JSON.
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    -- First time the world fetched it.
    delivered_at INTEGER,
    finished_at INTEGER,
    -- 1 if the world did it, 0 if it failed. NULL while it waits.
    ok INTEGER,
    message TEXT
) STRICT;

CREATE INDEX jobs_waiting ON jobs (world_id, created_at) WHERE finished_at IS NULL;
