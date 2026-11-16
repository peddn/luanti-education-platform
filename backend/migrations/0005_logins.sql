-- Logging in at the web application: links from mails and sessions.

-- When the last mail with a login link went out, to limit how often.
ALTER TABLE teachers ADD COLUMN last_login_mail_at INTEGER;

-- Links that log a teacher in. A link works once and for a short time.
-- Only the SHA-256 of its token is stored. Times are seconds since 1970
-- (UTC).
CREATE TABLE login_tokens (
    token_hash TEXT PRIMARY KEY,
    account TEXT NOT NULL REFERENCES teachers (account) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
) STRICT, WITHOUT ROWID;

CREATE INDEX login_tokens_by_account ON login_tokens (account);

-- Sessions of teachers who are logged in. The browser holds the token in
-- a cookie, the database only its SHA-256. A session ends at a fixed
-- time and is not extended.
CREATE TABLE sessions (
    token_hash TEXT PRIMARY KEY,
    account TEXT NOT NULL REFERENCES teachers (account) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
) STRICT, WITHOUT ROWID;

CREATE INDEX sessions_by_account ON sessions (account);
