-- One password for a teacher in all worlds.

-- What the worlds store of the password of a teacher: a salt and a
-- verifier, as the engine writes them. The password cannot be worked out
-- from it. NULL until a world has reported one, and after a new start
-- password was ordered.
ALTER TABLE staff_accounts ADD COLUMN password_entry TEXT;
-- Counts the passwords of the teacher. Every new one is a new version,
-- so a report about an older one changes nothing.
ALTER TABLE staff_accounts ADD COLUMN password_version INTEGER NOT NULL DEFAULT 0;

-- The worlds that have the account of a teacher, as each world said
-- last.
CREATE TABLE staff_worlds (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    account TEXT NOT NULL COLLATE NOCASE,
    -- 1 if the world has the password the backend keeps.
    in_step INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (world_id, account)
) STRICT;
