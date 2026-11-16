-- Ids for events. Pure Lua, no engine calls.

local ids = {}

local HEX = "0123456789abcdef"

--- Returns a random id in the form of a UUID, version 4.
-- @param random Function(min, max) returning a whole number in that range.
function ids.uuid(random)
	local parts = {}
	for index = 1, 32 do
		local value = random(0, 15)
		if index == 13 then
			-- The version.
			value = 4
		elseif index == 17 then
			-- The variant: 8, 9, a or b.
			value = 8 + value % 4
		end
		parts[index] = HEX:sub(value + 1, value + 1)
	end
	local text = table.concat(parts)
	return text:sub(1, 8) .. "-" .. text:sub(9, 12) .. "-" .. text:sub(13, 16) .. "-"
		.. text:sub(17, 20) .. "-" .. text:sub(21, 32)
end

return ids
