-- The account a job is about, for jobs that concern a single account.
-- A job that carries a password forgets it when it is done; who it was
-- for stays known, so the state of the account can be shown.
ALTER TABLE jobs ADD COLUMN subject TEXT;

CREATE INDEX jobs_by_subject ON jobs (world_id, kind, subject);
