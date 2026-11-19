-- Room types, room geometry and room assignment. Pure Lua, no engine calls.
--
-- Every room type has its own layer high above the world. On a layer the
-- rooms sit in the middle of square cells of PITCH nodes, so players in
-- neighbouring rooms are out of each other's range. A player gets one
-- fixed room per room type.

local rooms = {}

-- Distance between the centres of two rooms, horizontally and between
-- layers. Must never change: it defines where existing rooms are.
rooms.PITCH = 512
-- Height of layer 0.
rooms.BASE_Y = 10000
-- Largest allowed interior edge length of a room.
rooms.MAX_SIZE = 128
-- Cells are used up to this distance from the world centre.
rooms.MAX_CELL = 58
rooms.MAX_LAYER = 38
-- Number of rooms that fit on one layer.
rooms.CAPACITY = (2 * rooms.MAX_CELL + 1) ^ 2

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function is_int(value)
	return type(value) == "number" and value == math.floor(value)
end

local function copy_set(set)
	local result = {}
	for key, value in pairs(set or {}) do
		if value then
			result[key] = true
		end
	end
	return result
end

local function cell_key(i, j)
	return i .. "," .. j
end

--- Returns the cell (i, j) of a slot. Slots fill the grid in a square
-- spiral around the centre: slot 0 is (0, 0), then the ring around it.
function rooms.slot_to_cell(slot)
	assert(is_int(slot) and slot >= 0, "slot_to_cell: slot must be an integer >= 0")
	if slot == 0 then
		return 0, 0
	end
	-- Ring r holds the slots (2r-1)^2 .. (2r+1)^2 - 1.
	local ring = math.ceil((math.sqrt(slot + 1) - 1) / 2)
	local side = 2 * ring
	local offset = slot - (2 * ring - 1) ^ 2
	local edge = math.floor(offset / side)
	local step = offset % side
	if edge == 0 then
		return ring, -ring + 1 + step
	elseif edge == 1 then
		return ring - 1 - step, ring
	elseif edge == 2 then
		return -ring, ring - 1 - step
	end
	return -ring + 1 + step, -ring
end

-- ---------------------------------------------------------------------------
-- Room types
-- ---------------------------------------------------------------------------

local Types = {}
Types.__index = Types

--- Creates an empty registry of room types.
function rooms.new_types()
	return setmetatable({ _defs = {}, _by_layer = {} }, Types)
end

--- Registers a room type.
-- @param id Unique id, e.g. "lep_tz:room".
-- @param def Table with:
--   layer       integer 0..MAX_LAYER, unique. Must never change, it
--               defines the height of all rooms of this type.
--   size        interior size { x, y, z } in nodes
--   version     integer, default 1. Raise it to have existing rooms
--               rebuilt when they are entered the next time.
--   privileges  set of privileges granted inside the room
--   prebuild    boolean, default true. Whether rooms of this type are
--               built ahead when accounts are created. False for types
--               that not every student gets.
function Types:register(id, def)
	assert(type(id) == "string" and id ~= "", "register: id must be a non-empty string")
	assert(type(def) == "table", "register: def must be a table")
	assert(not self._defs[id], "register: room type '" .. id .. "' already exists")
	assert(is_int(def.layer) and def.layer >= 0 and def.layer <= rooms.MAX_LAYER,
		"register: layer must be an integer between 0 and " .. rooms.MAX_LAYER)
	assert(not self._by_layer[def.layer],
		"register: layer " .. def.layer .. " is already used by '"
		.. tostring(self._by_layer[def.layer]) .. "'")

	local size = def.size
	assert(type(size) == "table", "register: size must be a table")
	for _, axis in ipairs({ "x", "y", "z" }) do
		assert(is_int(size[axis]) and size[axis] >= 1 and size[axis] <= rooms.MAX_SIZE,
			"register: size." .. axis .. " must be an integer between 1 and "
			.. rooms.MAX_SIZE)
	end

	local version = def.version or 1
	assert(is_int(version) and version >= 1, "register: version must be an integer >= 1")
	assert(def.prebuild == nil or type(def.prebuild) == "boolean",
		"register: prebuild must be true or false")

	self._defs[id] = {
		id = id,
		layer = def.layer,
		size = { x = size.x, y = size.y, z = size.z },
		version = version,
		privileges = copy_set(def.privileges),
		prebuild = def.prebuild ~= false,
	}
	self._by_layer[def.layer] = id
end

function Types:get(id)
	return self._defs[id]
end

--- Returns the id of the room type on a layer, or nil.
function Types:id_on_layer(layer)
	return self._by_layer[layer]
end

--- Returns all room type ids, sorted.
function Types:ids()
	local ids = {}
	for id in pairs(self._defs) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

--- Returns the sorted ids of the room types that are built ahead when
-- accounts are created.
function Types:prebuild_ids()
	local ids = {}
	for _, id in ipairs(self:ids()) do
		if self._defs[id].prebuild then
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

--- Returns where a room is.
-- @param def Room type definition from Types:get.
-- @param slot Slot number of the room.
-- @return Table with
--   interior_min, interior_max  the space players can use
--   shell_min, shell_max        interior plus the one node thick shell
--   spawn                       where players stand after entering: on the
--                               floor, centred in x, at the front wall (-z).
--                               Always inside the interior.
function rooms.geometry(def, slot)
	local i, j = rooms.slot_to_cell(slot)
	assert(math.abs(i) <= rooms.MAX_CELL and math.abs(j) <= rooms.MAX_CELL,
		"geometry: slot " .. slot .. " is outside the usable area")

	local centre_x = i * rooms.PITCH
	local centre_z = j * rooms.PITCH
	local floor_y = rooms.BASE_Y + def.layer * rooms.PITCH

	local min = {
		x = centre_x - math.floor(def.size.x / 2),
		y = floor_y + 1,
		z = centre_z - math.floor(def.size.z / 2),
	}
	local max = {
		x = min.x + def.size.x - 1,
		y = min.y + def.size.y - 1,
		z = min.z + def.size.z - 1,
	}

	return {
		interior_min = min,
		interior_max = max,
		shell_min = { x = min.x - 1, y = min.y - 1, z = min.z - 1 },
		shell_max = { x = max.x + 1, y = max.y + 1, z = max.z + 1 },
		-- In a room that is only one node deep, the front is all there is.
		spawn = { x = centre_x, y = min.y, z = math.min(min.z + 1, max.z) },
	}
end

local function inside(pos, min, max)
	return pos.x >= min.x and pos.x <= max.x
		and pos.y >= min.y and pos.y <= max.y
		and pos.z >= min.z and pos.z <= max.z
end

-- ---------------------------------------------------------------------------
-- Assignment
-- ---------------------------------------------------------------------------

local Book = {}
Book.__index = Book

--- Creates the book that records which player has which room.
-- @param data Optional table from Book:export, e.g. loaded from storage.
function rooms.new_book(data)
	local book = setmetatable({ _types = {} }, Book)
	if type(data) == "table" and type(data.types) == "table" then
		for type_id, entry in pairs(data.types) do
			if type(type_id) == "string" and type(entry) == "table" then
				local records = {}
				local next_slot = 0
				for player, record in pairs(entry.rooms or {}) do
					if type(player) == "string" and type(record) == "table"
							and is_int(record.slot) and record.slot >= 0 then
						records[player] = {
							slot = record.slot,
							built_version = is_int(record.built_version)
								and record.built_version or nil,
						}
						next_slot = math.max(next_slot, record.slot + 1)
					end
				end
				if is_int(entry.next_slot) and entry.next_slot > next_slot then
					next_slot = entry.next_slot
				end
				book._types[type_id] = { next_slot = next_slot, rooms = records }
			end
		end
	end
	book:_reindex()
	return book
end

function Book:_reindex()
	self._cells = {}
	for type_id, entry in pairs(self._types) do
		local cells = {}
		for player, record in pairs(entry.rooms) do
			cells[cell_key(rooms.slot_to_cell(record.slot))] = player
		end
		self._cells[type_id] = cells
	end
end

--- Returns a plain table for storage.
function Book:export()
	local types = {}
	for type_id, entry in pairs(self._types) do
		local records = {}
		for player, record in pairs(entry.rooms) do
			records[player] = { slot = record.slot, built_version = record.built_version }
		end
		types[type_id] = { next_slot = entry.next_slot, rooms = records }
	end
	return { types = types }
end

--- Returns the room record of a player or nil.
-- A record has: slot, built_version (nil if never built).
function Book:get(type_id, player)
	local entry = self._types[type_id]
	return entry and entry.rooms[player] or nil
end

--- Returns the room record of a player, assigning a new room if needed.
-- A slot is never given to a second player.
-- @return record  or  nil, error message if the layer is full
function Book:assign(type_id, player)
	assert(type(type_id) == "string" and type_id ~= "", "assign: invalid type id")
	assert(type(player) == "string" and player ~= "", "assign: invalid player name")

	local entry = self._types[type_id]
	if not entry then
		entry = { next_slot = 0, rooms = {} }
		self._types[type_id] = entry
		self._cells[type_id] = {}
	end

	local record = entry.rooms[player]
	if not record then
		if entry.next_slot >= rooms.CAPACITY then
			return nil, "no free room left for type '" .. type_id .. "'"
		end
		record = { slot = entry.next_slot }
		entry.next_slot = entry.next_slot + 1
		entry.rooms[player] = record
		self._cells[type_id][cell_key(rooms.slot_to_cell(record.slot))] = player
	end
	return record
end

--- Forgets all rooms of a player. Their slots stay empty: a slot is
-- never given to a second player.
-- @return List of { type_id, slot } of the rooms the player had, sorted
--   by type.
function Book:remove(player)
	local list = {}
	for type_id, entry in pairs(self._types) do
		local record = entry.rooms[player]
		if record then
			list[#list + 1] = { type_id = type_id, slot = record.slot }
			entry.rooms[player] = nil
			self._cells[type_id][cell_key(rooms.slot_to_cell(record.slot))] = nil
		end
	end
	table.sort(list, function(a, b)
		return a.type_id < b.type_id
	end)
	return list
end

--- Records that a room was built with the given version.
function Book:mark_built(type_id, player, version)
	local record = self:get(type_id, player)
	assert(record, "mark_built: no room assigned")
	record.built_version = version
end

--- Returns true if the room has to be built before it can be used.
function Book:needs_build(type_id, player, version)
	local record = self:get(type_id, player)
	return record == nil or record.built_version ~= version
end

--- Returns the names of all players with a room of this type, sorted.
function Book:owners(type_id)
	local names = {}
	local entry = self._types[type_id]
	if entry then
		for player in pairs(entry.rooms) do
			names[#names + 1] = player
		end
	end
	table.sort(names)
	return names
end

--- Finds out what is at a position.
-- @return nil if the position is on no room layer, otherwise a table with
--   type_id  room type of the layer
--   owner    owner of the room in this cell, or nil if the cell is free
--   part     "interior", "shell" or "outside"
function rooms.locate(types, book, pos)
	local layer = math.floor((pos.y - rooms.BASE_Y) / rooms.PITCH)
	local type_id = types:id_on_layer(layer)
	if not type_id then
		return nil
	end
	local def = types:get(type_id)

	local i = math.floor(pos.x / rooms.PITCH + 0.5)
	local j = math.floor(pos.z / rooms.PITCH + 0.5)
	local cells = book._cells[type_id]
	local owner = cells and cells[cell_key(i, j)] or nil
	if not owner then
		return { type_id = type_id, owner = nil, part = "outside" }
	end

	local geometry = rooms.geometry(def, book:get(type_id, owner).slot)
	local part = "outside"
	if inside(pos, geometry.interior_min, geometry.interior_max) then
		part = "interior"
	elseif inside(pos, geometry.shell_min, geometry.shell_max) then
		part = "shell"
	end
	return { type_id = type_id, owner = owner, part = part }
end

--- Decides whether a player may build or dig at a position.
-- @return true (allowed), false (forbidden) or nil (not on a room layer,
--         the caller should ask someone else)
function rooms.may_modify(types, book, pos, player)
	local where = rooms.locate(types, book, pos)
	if not where then
		return nil
	end
	return where.part == "interior" and where.owner == player
end

return rooms
