-- Decides when the lobby music starts and stops. Pure Lua, no engine calls.

local music = {}

music.START = "start"
music.STOP = "stop"

--- Returns what to do when a player is now at a place.
-- @param lobby The place id of the lobby.
-- @param place The place the player is at now, or nil if they left the game.
-- @param playing True if the music is playing for this player.
-- @return music.START, music.STOP or nil for "nothing to do".
function music.action(lobby, place, playing)
	if place == lobby then
		if not playing then
			return music.START
		end
	elseif playing then
		return music.STOP
	end
	return nil
end

return music
