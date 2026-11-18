-- The display name an account chose in its world, as the world reported
-- it last. The worlds write, the backend mirrors.
CREATE TABLE display_names (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    account TEXT NOT NULL,
    -- NULL while the account name is shown.
    name TEXT,
    -- When the player chose a name last, by the clock of the world.
    changed_at INTEGER,
    locked INTEGER NOT NULL DEFAULT 0,
    -- Time of the event this state came with. An older one is dropped.
    reported_at INTEGER NOT NULL,
    PRIMARY KEY (world_id, account)
) STRICT, WITHOUT ROWID;
