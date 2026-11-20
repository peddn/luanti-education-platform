-- Whether a world runs, as the agent last reported it. NULL for a world
-- the agent does not run.
ALTER TABLE worlds ADD COLUMN running INTEGER;
