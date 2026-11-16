-- Teachers and their web access.

-- A teacher is an account name, across all worlds. A row exists once a
-- teacher has entered an address at the desk. Times are seconds since
-- 1970 (UTC).
CREATE TABLE teachers (
    account TEXT PRIMARY KEY,
    -- The confirmed address, in lower case. An address belongs to at most
    -- one account.
    email TEXT UNIQUE,
    -- The address that waits for its confirmation. The confirmed one
    -- stays valid until then.
    pending_email TEXT,
    -- SHA-256 of the token in the confirmation mail. The token itself is
    -- only in the mail.
    token_hash TEXT UNIQUE,
    token_expires_at INTEGER,
    -- When the last confirmation mail went out, to limit how often.
    last_mail_at INTEGER,
    created_at INTEGER NOT NULL,
    confirmed_at INTEGER
) STRICT;

-- The worlds in which an account holds the privilege for web access, as
-- each world reports it. Without a row here the web access is blocked.
CREATE TABLE teacher_worlds (
    world_id TEXT NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    account TEXT NOT NULL,
    PRIMARY KEY (world_id, account)
) STRICT, WITHOUT ROWID;

CREATE INDEX teacher_worlds_by_account ON teacher_worlds (account);
