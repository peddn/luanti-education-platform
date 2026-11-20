-- Version of the template for worlds the agent carries, as it last
-- reported. NULL if it has none.
ALTER TABLE game_server ADD COLUMN template_version TEXT;
