-- One password for a teacher in all worlds.

-- What the worlds store of the password of a teacher: a salt and a
-- verifier, as the engine writes them. The password cannot be worked out
-- from it. The backend works it out when it gives out a password, sends
-- it to every world, and keeps it for the worlds that come later.
ALTER TABLE staff_accounts ADD COLUMN password_entry TEXT;
