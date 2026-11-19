-- When the year was closed: the one moment data is deleted on a large
-- scale. Kept for good, without any content: who, when, how much.
CREATE TABLE year_ends (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    -- When it was started, in seconds since 1970.
    time INTEGER NOT NULL,
    -- Account name of the member of the school administration.
    account TEXT NOT NULL,
    -- How much was deleted here.
    groups INTEGER NOT NULL,
    protocol_entries INTEGER NOT NULL,
    exports INTEGER NOT NULL
) STRICT;
