-- Jobs for the agent go through the same queue as jobs for the worlds.
-- Every job names who is to do it: 'world' or 'agent'. A job for the
-- agent is still about one world.
ALTER TABLE jobs ADD COLUMN recipient TEXT NOT NULL DEFAULT 'world';

DROP INDEX jobs_waiting;
CREATE INDEX jobs_waiting ON jobs (recipient, world_id, created_at) WHERE finished_at IS NULL;

-- What the agent last reported about a world it runs: its port and the
-- version of the template it uses. NULL for a world the agent does not
-- know, for example one that was set up by hand.
ALTER TABLE worlds ADD COLUMN port INTEGER;
ALTER TABLE worlds ADD COLUMN template_version TEXT;
