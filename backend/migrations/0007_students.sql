-- Accounts of students, and where players reach a world.

-- Printed on the access slips. Entered by the school administration
-- until the agent reports it.
ALTER TABLE worlds ADD COLUMN address TEXT;

-- The accounts of the students of a group. The name is rolled by the
-- backend and says nothing about the person; who is behind it only the
-- teacher knows. A name is taken once at the whole school, whatever the
-- letter case. Passwords are never stored here.
CREATE TABLE students (
    account TEXT PRIMARY KEY COLLATE NOCASE,
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    -- 'draft', 'creating', 'active' or 'refused'.
    state TEXT NOT NULL,
    created_at INTEGER NOT NULL
) STRICT;

CREATE INDEX students_by_world ON students (world_id);
