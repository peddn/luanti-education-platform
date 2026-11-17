-- Groups: who belongs to the school administration and which teacher
-- looks after which group. A group is a world, one to one.

-- The worlds in which an account holds the privilege of the school
-- administration, as each world reports it.
CREATE TABLE school_admin_worlds (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    account TEXT NOT NULL,
    PRIMARY KEY (world_id, account)
) STRICT, WITHOUT ROWID;

CREATE INDEX school_admin_worlds_by_account ON school_admin_worlds (account);

-- The teachers of a group, as the school administration assigned them.
CREATE TABLE group_teachers (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    account TEXT NOT NULL,
    PRIMARY KEY (world_id, account)
) STRICT, WITHOUT ROWID;

CREATE INDEX group_teachers_by_account ON group_teachers (account);
