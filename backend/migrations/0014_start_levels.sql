-- The level players start a module on about whom the world has stored
-- nothing yet, as the world reported it with its modules. Set per group
-- by a teacher; the world keeps it, the backend mirrors.
ALTER TABLE modules ADD COLUMN start_level INTEGER NOT NULL DEFAULT 1;
