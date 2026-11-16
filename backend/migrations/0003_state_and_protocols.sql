-- What the worlds report: the state of the students, which stays with
-- the account, and the protocols, which are deleted with the end of the
-- school year. The worlds write, the backend mirrors.

-- The learning modules a world knows, replaced as a whole.
CREATE TABLE modules (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    module_id TEXT NOT NULL,
    title TEXT NOT NULL,
    -- Levels with their kinds of tasks, as JSON.
    levels TEXT NOT NULL,
    -- Position in the list the world sent.
    position INTEGER NOT NULL,
    PRIMARY KEY (world_id, module_id)
) STRICT, WITHOUT ROWID;

-- Where a student stands in a module. Only the state, never how it came
-- about.
CREATE TABLE progress (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    account TEXT NOT NULL,
    module_id TEXT NOT NULL,
    level INTEGER NOT NULL,
    locked INTEGER NOT NULL,
    percent INTEGER NOT NULL,
    completed INTEGER NOT NULL,
    -- Kinds of tasks of the level with solved and required, as JSON.
    tasks TEXT NOT NULL,
    -- Time of the event this state came with.
    reported_at INTEGER NOT NULL,
    PRIMARY KEY (world_id, account, module_id)
) STRICT, WITHOUT ROWID;

-- The trophies a student has earned.
CREATE TABLE trophies (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    account TEXT NOT NULL,
    trophy_id TEXT NOT NULL,
    title TEXT NOT NULL,
    material TEXT NOT NULL,
    PRIMARY KEY (world_id, account, trophy_id)
) STRICT, WITHOUT ROWID;

-- Time of the newest list of trophies per student, so an older list that
-- arrives late changes nothing.
CREATE TABLE trophy_reports (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    account TEXT NOT NULL,
    reported_at INTEGER NOT NULL,
    PRIMARY KEY (world_id, account)
) STRICT, WITHOUT ROWID;

-- Entries of the protocols of the worlds: rewards, chat, sign texts and
-- actions at the teacher's desk. All of them are data of the running
-- school year.
CREATE TABLE protocol_entries (
    id INTEGER PRIMARY KEY,
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    protocol TEXT NOT NULL,
    -- When it happened in the world.
    time INTEGER NOT NULL,
    -- Account name, never a display name.
    account TEXT NOT NULL,
    -- The other columns of the entry as a JSON object.
    fields TEXT NOT NULL
) STRICT;

CREATE INDEX protocol_entries_by_time ON protocol_entries (world_id, protocol, time);
CREATE INDEX protocol_entries_by_account ON protocol_entries (world_id, account, time);
