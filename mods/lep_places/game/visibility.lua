-- How far players see each other.
--
-- By default the engine shows every player to every client, however far
-- away: name tags of people in the lobby or in a learning room, thousands
-- of nodes up, show in the sky above the wilderness. Places are meant to
-- be apart, so the distance gets a limit unless the server sets its own.

local SETTING = "player_transfer_distance"
-- In map blocks of 16 nodes: 160 nodes.
local DEFAULT_BLOCKS = 10

if not core.settings:has(SETTING) then
	-- The engine reads the setting all the time, so this works at once.
	core.settings:set(SETTING, tostring(DEFAULT_BLOCKS))
	core.log("action", "[lep_places] players see each other up to "
		.. DEFAULT_BLOCKS * 16 .. " nodes (" .. SETTING .. " = " .. DEFAULT_BLOCKS .. ")")
end
