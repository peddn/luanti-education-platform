-- Corridors and personal rooms of the lobby. Pure Lua, no engine calls.
--
-- Four corridors leave the hall, one in each horizontal direction. Rooms
-- line both sides of each corridor. Every player owns one room, numbered
-- by a slot. Slots fill the four corridors evenly, so no corridor grows
-- much longer than the others.
--
-- All coordinates are relative to the hall origin: the centre of the hall
-- floor, with the floor at y = 0. Inside one corridor a position is given
-- as "axial" (distance from the origin along the corridor) and "lateral"
-- (sideways, 0 is the middle of the corridor).

local corridors = {}

-- Raise this when the shape changes, so existing corridors are rebuilt.
corridors.VERSION = 4

-- Axial position of the opening in the hall wall: hall radius + 1.
corridors.OPENING = 16
-- Axial position of the first room wall.
corridors.FIRST_WALL = 19
-- Distance between two room walls: 5 nodes of room and one shared wall.
corridors.PITCH = 6
-- Inner size of a room.
corridors.ROOM_SIZE = 5
-- Inner depth of a room, away from the corridor. Depth costs no walking
-- distance in the corridor, so rooms are deeper than wide.
corridors.ROOM_DEPTH = 7
corridors.ROOM_HEIGHT = 4
-- Inner height of the corridor. Its inner width is 3.
corridors.HEIGHT = 3

corridors.DIRECTIONS = 4
corridors.SLOTS_PER_ROW = corridors.DIRECTIONS * 2

-- Node kinds returned by corridors.kind_at.
corridors.FLOOR = "floor"
corridors.GLASS = "glass"
corridors.LAMP = "lamp"
corridors.AIR = "air"
corridors.SIGN = "sign"
-- Solid wall of a room.
corridors.WALL = "wall"
-- Lower and upper half of a room door.
corridors.DOOR = "door"
corridors.DOOR_TOP = "door_top"

local OPENING = corridors.OPENING
local FIRST_WALL = corridors.FIRST_WALL
local PITCH = corridors.PITCH
local DOOR_OFFSET = 3
local SIDE = 2
local OUTER_WALL = SIDE + corridors.ROOM_DEPTH + 1
-- Depth of the lamps in floor and ceiling: the middle of the room.
local LAMP_DEPTH = SIDE + math.ceil(corridors.ROOM_DEPTH / 2)
-- Trophy pedestals stand in three rows behind the row at the door.
local PEDESTAL_FIRST = SIDE + 2
local PEDESTAL_LAST = SIDE + 4
local ROOM_CEILING = corridors.ROOM_HEIGHT + 1
local CEILING = corridors.HEIGHT + 1

-- Axial and lateral unit vectors of the four corridors, as { x, z }.
local AXES = {
	{ axial = { 1, 0 }, lateral = { 0, 1 } },
	{ axial = { 0, 1 }, lateral = { -1, 0 } },
	{ axial = { -1, 0 }, lateral = { 0, -1 } },
	{ axial = { 0, -1 }, lateral = { 1, 0 } },
}

local function to_relative(direction, axial, lateral, y)
	local axes = AXES[direction]
	return {
		x = axial * axes.axial[1] + lateral * axes.lateral[1],
		y = y,
		z = axial * axes.axial[2] + lateral * axes.lateral[2],
	}
end

local function to_corridor(direction, x, z)
	local axes = AXES[direction]
	return x * axes.axial[1] + z * axes.axial[2],
		x * axes.lateral[1] + z * axes.lateral[2]
end

--- Splits a slot number (0, 1, 2, ...) into corridor (1..4), side (1 or -1)
-- and row along the corridor (0, 1, 2, ...).
function corridors.slot_position(slot)
	assert(type(slot) == "number" and slot >= 0 and slot == math.floor(slot),
		"slot must be a non-negative integer")
	local direction = slot % corridors.DIRECTIONS + 1
	local side = math.floor(slot / corridors.DIRECTIONS) % 2 == 0 and 1 or -1
	local row = math.floor(slot / corridors.SLOTS_PER_ROW)
	return direction, side, row
end

local function slot_at(direction, side, row)
	return row * corridors.SLOTS_PER_ROW
		+ (side == 1 and 0 or corridors.DIRECTIONS) + direction - 1
end

--- Returns how many rows of rooms a corridor has when `count` slots are
-- in use.
function corridors.rows(direction, count)
	local rows = 0
	for side = 1, -1, -2 do
		local first = slot_at(direction, side, 0)
		if count > first then
			rows = math.max(rows,
				math.floor((count - 1 - first) / corridors.SLOTS_PER_ROW) + 1)
		end
	end
	return rows
end

-- Axial position of the glass wall that closes the corridor.
local function end_wall(direction, count)
	return FIRST_WALL + PITCH * corridors.rows(direction, count)
end

--- Returns the lowest and highest relative coordinates of one corridor
-- with its rooms.
function corridors.bounds(direction, count)
	local a = to_relative(direction, OPENING, -OUTER_WALL, 0)
	local b = to_relative(direction, end_wall(direction, count), OUTER_WALL, ROOM_CEILING)
	return { x = math.min(a.x, b.x), y = 0, z = math.min(a.z, b.z) },
		{ x = math.max(a.x, b.x), y = ROOM_CEILING, z = math.max(a.z, b.z) }
end

local function room_kind(direction, count, axial, lateral, y)
	for side = 1, -1, -2 do
		local across = lateral * side
		if across >= SIDE and across <= OUTER_WALL and axial >= FIRST_WALL then
			local row = math.floor((axial - FIRST_WALL) / PITCH)
			local along = (axial - FIRST_WALL) - row * PITCH
			-- A wall between two rooms belongs to both.
			local exists = slot_at(direction, side, row) < count
				or (along == 0 and row > 0 and slot_at(direction, side, row - 1) < count)
			if exists then
				local centre = along == DOOR_OFFSET and across == LAMP_DEPTH
				if y == 0 then
					return centre and corridors.LAMP or corridors.FLOOR
				elseif y == ROOM_CEILING then
					return centre and corridors.LAMP or corridors.WALL
				elseif across == OUTER_WALL or along == 0 then
					return corridors.WALL
				elseif across == SIDE then
					if along == DOOR_OFFSET and y <= 2 then
						local slot = slot_at(direction, side, row)
						return y == 1 and corridors.DOOR or corridors.DOOR_TOP, slot
					end
					return corridors.WALL
				end
				return corridors.AIR
			end
		end
	end
	return nil
end

local function kind_in_corridor(direction, count, axial, lateral, y)
	if y < 0 or y > ROOM_CEILING then
		return nil
	end

	-- The opening in the hall wall.
	if axial == OPENING then
		if math.abs(lateral) <= 1 and y >= 1 and y <= corridors.HEIGHT then
			return corridors.AIR
		end
		return nil
	end

	local last = end_wall(direction, count)
	if axial < OPENING or axial > last then
		return nil
	end

	local kind, slot = room_kind(direction, count, axial, lateral, y)
	if kind then
		return kind, slot
	end

	if math.abs(lateral) > SIDE or y > CEILING then
		return nil
	elseif y == 0 then
		if lateral == 0 and axial < last then
			return corridors.LAMP
		end
		return corridors.FLOOR
	elseif y == CEILING or math.abs(lateral) == SIDE or axial == last then
		return corridors.GLASS
	end

	-- Name signs hang above the doors, inside the corridor.
	if y == corridors.HEIGHT and lateral ~= 0 and axial > FIRST_WALL then
		local row = math.floor((axial - FIRST_WALL) / PITCH)
		local along = (axial - FIRST_WALL) - row * PITCH
		local sign_slot = slot_at(direction, lateral, row)
		if along == DOOR_OFFSET and sign_slot < count then
			return corridors.SIGN, sign_slot
		end
	end
	return corridors.AIR
end

--- Returns what belongs at a position relative to the hall origin when
-- `count` slots are in use: one of the kinds above, or nil if the position
-- is not part of a corridor or room. For corridors.SIGN, corridors.DOOR
-- and corridors.DOOR_TOP the slot number is the second return value.
function corridors.kind_at(x, y, z, count)
	for direction = 1, corridors.DIRECTIONS do
		local axial, lateral = to_corridor(direction, x, z)
		if axial >= OPENING and math.abs(lateral) <= OUTER_WALL then
			return kind_in_corridor(direction, count, axial, lateral, y)
		end
	end
	return nil
end

--- Returns the important spots of the room of a slot, relative to the
-- hall origin:
--   entrance   where a player stands in the corridor in front of the door
--   look_dir   direction from the entrance towards the door, as { x, z }
--   door       position of the lower half of the door
--   sign       position of the name sign
--   sign_wall  direction from the sign to the wall it hangs on
--   interior_min, interior_max  the inside of the room
--   portal     spot for the personal portal
--   chest      spot for the reward chest
--   pedestals  six spots for trophy pedestals: three at each side wall
function corridors.room(slot)
	local direction, side, row = corridors.slot_position(slot)
	local door = FIRST_WALL + PITCH * row + DOOR_OFFSET
	local first = FIRST_WALL + PITCH * row + 1
	local last = first + corridors.ROOM_SIZE - 1

	local a = to_relative(direction, first, side * (SIDE + 1), 1)
	local b = to_relative(direction, last, side * (OUTER_WALL - 1), corridors.ROOM_HEIGHT)
	local wall = to_relative(direction, 0, side, 0)

	-- Seen from the door: three at the wall on one side, then three at the
	-- other. The row at the door stays free, and so do the two rows at the
	-- back, so portal and chest are easy to reach.
	local pedestals = {}
	for _, axial in ipairs({ first, last }) do
		for depth = PEDESTAL_FIRST, PEDESTAL_LAST do
			pedestals[#pedestals + 1] = to_relative(direction, axial, side * depth, 1)
		end
	end

	return {
		direction = direction,
		entrance = to_relative(direction, door, 0, 1),
		look_dir = { x = wall.x, z = wall.z },
		door = to_relative(direction, door, side * SIDE, 1),
		sign = to_relative(direction, door, side, corridors.HEIGHT),
		sign_wall = wall,
		interior_min = { x = math.min(a.x, b.x), y = 1, z = math.min(a.z, b.z) },
		interior_max = {
			x = math.max(a.x, b.x), y = corridors.ROOM_HEIGHT, z = math.max(a.z, b.z),
		},
		portal = to_relative(direction, door, side * (OUTER_WALL - 1), 1),
		chest = to_relative(direction, first, side * (OUTER_WALL - 1), 1),
		pedestals = pedestals,
	}
end

--- Returns where each corridor starts and in which direction it runs,
-- relative to the hall origin. A hand-built hall provides the same list.
function corridors.starts()
	local list = {}
	for direction = 1, corridors.DIRECTIONS do
		local axes = AXES[direction]
		list[direction] = {
			start = to_relative(direction, OPENING + 1, 0, 1),
			dir = { x = axes.axial[1], y = 0, z = axes.axial[2] },
		}
	end
	return list
end

--- Returns the text for the name sign of a room. Account names are an
-- adjective and a noun, like "klugeEule": the two parts go on two lines,
-- so the letters can be large. The name is split where a capital letter
-- follows a small one, or at an underscore. A display name with a space
-- is split there. A name without such a place stays on one line.
function corridors.sign_text(name)
	if type(name) ~= "string" then
		return ""
	end
	local first, second = name:match("^(.-) (.*)$")
	if first then
		return first .. "\n" .. second
	end
	first, second = name:match("^(.-%l)(%u.*)$")
	if first then
		return first .. "\n" .. second
	end
	return (name:gsub("_", "\n", 1))
end

--- Returns true if the position is inside the room of a slot.
function corridors.is_in_room(slot, x, y, z)
	local room = corridors.room(slot)
	local min, max = room.interior_min, room.interior_max
	return x >= min.x and x <= max.x and y >= min.y and y <= max.y
		and z >= min.z and z <= max.z
end

--- Decides whether a player may open or close the door of a room.
-- The owner and staff always may. Everyone else may only open a closed
-- door from the inside: a closed door keeps visitors out but never locks
-- anyone in, and a visitor can never close it.
function corridors.may_use_door(is_owner, is_staff, is_inside, is_open)
	if is_owner == true or is_staff == true then
		return true
	end
	return is_inside == true and is_open ~= true
end

--- Creates the book that records which player owns which slot.
-- @param data Table from an earlier export, or nil for an empty book.
function corridors.new_book(data)
	local owners = {}
	local names = {}
	local count = 0

	if type(data) == "table" and type(data.owners) == "table" then
		for name, slot in pairs(data.owners) do
			if type(name) == "string" and type(slot) == "number"
					and slot >= 0 and slot == math.floor(slot) and not names[slot] then
				owners[name] = slot
				names[slot] = name
				count = math.max(count, slot + 1)
			end
		end
	end

	local book = {}

	--- Returns the slot of a player, or nil.
	function book.get(_, name)
		return owners[name]
	end

	--- Returns the owner of a slot, or nil.
	function book.owner(_, slot)
		return names[slot]
	end

	--- Returns the slot of a player, assigning the next free one if needed.
	-- @return slot, true if it was newly assigned
	function book.assign(_, name)
		assert(type(name) == "string" and name ~= "", "assign: name must be a string")
		if owners[name] then
			return owners[name], false
		end
		local slot = count
		owners[name] = slot
		names[slot] = name
		count = count + 1
		return slot, true
	end

	--- Returns the number of slots in use. Slots are never given back.
	function book.count(_)
		return count
	end

	--- Returns a plain table for storage.
	function book.export(_)
		local copy = {}
		for name, slot in pairs(owners) do
			copy[name] = slot
		end
		return { owners = copy }
	end

	return book
end

return corridors
