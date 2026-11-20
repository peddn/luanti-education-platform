-- The reward table of each world as the world reported it, and the
-- items a teacher may choose from. The world keeps both; this is the
-- mirror.
CREATE TABLE reward_tables (
    world_id TEXT PRIMARY KEY REFERENCES worlds (id) ON DELETE CASCADE,
    -- The table as JSON, see lep_protocol::world::RewardTable.
    reward_table TEXT NOT NULL,
    -- The choices as a JSON list of { name, title }.
    choices TEXT NOT NULL,
    reported_at INTEGER NOT NULL
) STRICT;
