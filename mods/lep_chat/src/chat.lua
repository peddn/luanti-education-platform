-- Rules of the chat. Pure Lua, no engine calls.

local chat = {}

-- Kinds of messages in the protocol.
chat.KIND_CHAT = "chat"         -- to everybody
chat.KIND_PRIVATE = "private"   -- /msg, to one player
chat.KIND_ACTION = "action"     -- /me

--- Splits the parameter of /msg into recipient and message, as the engine
-- does. Returns nil if it is not a valid private message.
function chat.parse_private(param)
	if type(param) ~= "string" then
		return nil
	end
	local recipient, message = param:match("^(%S+)%s(.+)$")
	if not recipient then
		return nil
	end
	return recipient, message
end

--------------------------------------------------------------------------
-- Mutes

-- The list of the players a teacher muted. It only holds players who
-- could speak before, so lifting a mute never gives anybody more than
-- they had.

local Mutes = {}
Mutes.__index = Mutes

--- Creates a list, empty or from the table that Mutes:data returned.
function chat.new_mutes(data)
	local mutes = setmetatable({ _names = {} }, Mutes)
	if type(data) == "table" then
		for _, name in ipairs(data) do
			if type(name) == "string" and name ~= "" then
				mutes._names[name] = true
			end
		end
	end
	return mutes
end

--- Returns the names as a sorted list, for saving.
function Mutes:data()
	local list = {}
	for name in pairs(self._names) do
		list[#list + 1] = name
	end
	table.sort(list)
	return list
end

--- Mutes a player. Returns true if something has to be done: the player
-- could speak and is not muted yet.
-- @param can_speak True if the player may write in the chat right now.
function Mutes:mute(player_name, can_speak)
	if self._names[player_name] or not can_speak then
		return false
	end
	self._names[player_name] = true
	return true
end

--- Lifts the mute of a player. Returns true if the player was muted.
function Mutes:unmute(player_name)
	if not self._names[player_name] then
		return false
	end
	self._names[player_name] = nil
	return true
end

--- Returns true if a teacher muted this player.
function Mutes:is_muted(player_name)
	return self._names[player_name] == true
end

--- Lifts all mutes. Returns the names of the players who were muted.
function Mutes:unmute_all()
	local list = self:data()
	self._names = {}
	return list
end

return chat
