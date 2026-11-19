-- Who is in the attention mode and where they come back to. Pure Lua, no
-- engine calls.
--
-- A teacher who wants the attention of students moves them into a dark
-- cell. For every student the list keeps the origin: place, position and
-- whether they were held there. The mode can end while a student is
-- offline; then the origin waits until they join again.

local attention = {}

attention.DEFAULT_TEXT = "Please pay attention to your teacher."
-- Longest text that is shown.
attention.MAX_TEXT = 200

local function is_pos(pos)
	return type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
		and type(pos.z) == "number"
end

local function copy_origin(origin)
	return {
		place = origin.place,
		pos = { x = origin.pos.x, y = origin.pos.y, z = origin.pos.z },
		held = origin.held == true,
	}
end

local function is_origin(origin)
	return type(origin) == "table" and type(origin.place) == "string" and origin.place ~= ""
		and is_pos(origin.pos)
end

--- Returns the text to show: what the teacher typed, trimmed and cut, or
-- nil if that is empty, so the caller uses the default.
function attention.clean_text(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, attention.MAX_TEXT)
	if text == "" then
		return nil
	end
	return text
end

local List = {}
List.__index = List

--- Creates a list, empty or from the table that List:data returned.
-- Entries that cannot be read are dropped.
function attention.new(data)
	local list = setmetatable({ _entries = {} }, List)
	if type(data) == "table" then
		for name, entry in pairs(data) do
			if type(name) == "string" and type(entry) == "table" and is_origin(entry.origin) then
				list._entries[name] = {
					origin = copy_origin(entry.origin),
					active = entry.active == true,
					text = type(entry.text) == "string" and entry.text or nil,
				}
			end
		end
	end
	return list
end

--- Returns a plain table with everything, for saving.
function List:data()
	local data = {}
	for name, entry in pairs(self._entries) do
		data[name] = { origin = copy_origin(entry.origin), active = entry.active,
			text = entry.text }
	end
	return data
end

--- Starts the mode for a player.
-- @param origin Table with place, pos and held: where the player is now.
-- @param text Text of the teacher or nil.
-- @return true if the player has to be moved into the cell, false if the
--   player was in the mode already and only the text changed
function List:start(player_name, origin, text)
	local entry = self._entries[player_name]
	if entry and entry.active then
		entry.text = text
		return false
	end
	assert(is_origin(origin), "origin must have a place and a position")
	-- A player whose return is still waiting keeps the older origin: it is
	-- where they really came from.
	self._entries[player_name] = {
		origin = entry and entry.origin or copy_origin(origin),
		active = true,
		text = text,
	}
	return true
end

--- Returns true if a player is in the mode.
function List:is_active(player_name)
	local entry = self._entries[player_name]
	return entry ~= nil and entry.active
end

--- Returns the text of the teacher for a player, or nil.
function List:get_text(player_name)
	local entry = self._entries[player_name]
	return entry and entry.text
end

--- Returns the names of the players in the mode, sorted.
function List:active_names()
	local names = {}
	for name, entry in pairs(self._entries) do
		if entry.active then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

--- Ends the mode for a player. The origin stays until the player was
-- brought back, see List:take_origin.
-- @return true if the player was in the mode
function List:stop(player_name)
	local entry = self._entries[player_name]
	if not entry or not entry.active then
		return false
	end
	entry.active = false
	entry.text = nil
	return true
end

--- Forgets a player altogether: the mode and where they came from. For
-- an account that is removed.
-- @return true if there was something to forget
function List:forget(player_name)
	local known = self._entries[player_name] ~= nil
	self._entries[player_name] = nil
	return known
end

--- Forgets that players were held where they came from. Used when the
-- last teacher leaves: from then on nobody is held anywhere.
function List:forget_holds()
	for _, entry in pairs(self._entries) do
		entry.origin.held = false
	end
end

--- Returns true if the mode ended for a player who was not brought back
-- yet.
function List:awaits_return(player_name)
	local entry = self._entries[player_name]
	return entry ~= nil and not entry.active
end

--- Returns the origin of a player whose mode has ended and forgets the
-- player. Returns nil if there is nothing to return to, or if the player
-- is still in the mode.
function List:take_origin(player_name)
	local entry = self._entries[player_name]
	if not entry or entry.active then
		return nil
	end
	self._entries[player_name] = nil
	return entry.origin
end

return attention
