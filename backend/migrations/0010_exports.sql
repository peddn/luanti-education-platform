-- Who downloaded which protocol as a file. The file leaves the platform,
-- so the school administration can see that it happened. The content of
-- the file is not kept. Written by the backend itself: the worlds know
-- nothing of exports.
CREATE TABLE exports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    -- When the file was made, in seconds since 1970.
    time INTEGER NOT NULL,
    -- Account name of the teacher.
    account TEXT NOT NULL,
    -- The protocol that was exported.
    protocol TEXT NOT NULL,
    -- The filters of the export, NULL where there was none.
    filter_account TEXT,
    filter_since INTEGER,
    -- How many entries the file held.
    entries INTEGER NOT NULL
) STRICT;

CREATE INDEX exports_by_world ON exports (world_id, id);
