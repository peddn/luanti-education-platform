-- Accounts of teachers the school administration ordered in the web
-- application. They exist in every world. An account that stands here
-- stays listed even when no world reports it as a teacher any more, so
-- it can still be deleted.
CREATE TABLE staff_accounts (
    account TEXT PRIMARY KEY COLLATE NOCASE,
    -- 'creating', 'active' or 'refused'.
    state TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    -- Account name of the member of the school administration.
    created_by TEXT NOT NULL
) STRICT;
