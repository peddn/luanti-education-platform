-- Deleting an account on request.

-- Whether somebody has ever logged in with an account, as the world
-- said. A teacher may take back an account nobody used; a used one only
-- the school administration deletes.
ALTER TABLE students ADD COLUMN used INTEGER NOT NULL DEFAULT 0;

-- The accounts that were deleted on request. Kept for good, without any
-- content: who, when, which account, in which group. The name of the
-- group is copied, so the note outlives the group. A name that stands
-- here is never rolled again.
CREATE TABLE account_removals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    -- When the world reported it, in seconds since 1970.
    time INTEGER NOT NULL,
    account TEXT NOT NULL COLLATE NOCASE,
    world_id TEXT NOT NULL,
    group_name TEXT NOT NULL,
    -- Account name of who ordered it. NULL if it was done in the world
    -- itself.
    ordered_by TEXT
) STRICT;

CREATE INDEX account_removals_by_account ON account_removals (account);
