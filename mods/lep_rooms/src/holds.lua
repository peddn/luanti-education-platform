-- Who is held in a learning room. Pure Lua, no engine calls.
--
-- A teacher who sends a student into a learning room holds them there:
-- the student cannot leave on their own until they are brought back or
-- released. The list lives in memory only. After a restart of the server
-- nobody is held.

local holds = {}

local Holds = {}
Holds.__index = Holds

--- Creates an empty list.
function holds.new()
	return setmetatable({ _names = {} }, Holds)
end

--- Holds a player. Returns true if the player was not held before.
function Holds:hold(player_name)
	assert(type(player_name) == "string" and player_name ~= "",
		"player name must be a non-empty string")
	if self._names[player_name] then
		return false
	end
	self._names[player_name] = true
	return true
end

--- Releases a player. Returns true if the player was held.
function Holds:release(player_name)
	if not self._names[player_name] then
		return false
	end
	self._names[player_name] = nil
	return true
end

--- Returns true if a player is held.
function Holds:is_held(player_name)
	return self._names[player_name] == true
end

--- Releases everybody. Returns the names of those who were held, sorted.
function Holds:release_all()
	local names = {}
	for name in pairs(self._names) do
		names[#names + 1] = name
	end
	table.sort(names)
	self._names = {}
	return names
end

return holds
