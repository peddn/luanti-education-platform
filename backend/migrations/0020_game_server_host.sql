-- Name under which players reach the game server, as the agent reported
-- it. With the port of a world it makes the address on the access slips.
-- NULL if the settings of the agent name none.
ALTER TABLE game_server ADD COLUMN host TEXT;
