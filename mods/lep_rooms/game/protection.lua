-- Protects the room layers: only the owner may build inside their room,
-- nobody may touch shells or the space between rooms.

local rooms = lep_rooms._rooms
local types = lep_rooms._types
local book = lep_rooms._book

local old_is_protected = core.is_protected

function core.is_protected(pos, name)
	local allowed = rooms.may_modify(types, book, pos, name)
	if allowed == nil then
		return old_is_protected(pos, name)
	end
	return not allowed
end
