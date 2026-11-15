-- Public API of lep_lobby and the building of hall, corridors and rooms.

local load = lep_core.loader("lep_lobby")
local provider = load("game/generated_hall")
local corridors = load("src/corridors")
local builder = load("game/corridors")

-- The hall hangs below the room layers, off the room grid, so no learning
-- room is ever directly above it.
local ORIGIN = { x = 256, y = 9000, z = 256 }
local PLACE = "lep_lobby:lobby"
local BUILT_KEY = "built_version"
local BOOK_KEY = "rooms"
-- Hall and corridors are rebuilt when either of them changes.
local VERSION = provider.version .. ":" .. corridors.VERSION

local mod_storage = core.get_mod_storage()
local anchors = provider.anchors(ORIGIN)
local ready = mod_storage:get_string(BUILT_KEY) == VERSION
local book = corridors.new_book(core.deserialize(mod_storage:get_string(BOOK_KEY)))
local waiting = {}

lep_lobby.PLACE = PLACE

lep_places.register_place(PLACE, { default_pos = anchors.spawn })

local function get_count()
	return book:count()
end

local function get_owner(slot)
	return book:owner(slot)
end

local function build(callback)
	provider.build(ORIGIN, function()
		-- The hall closes its wall again, so the corridors come after it.
		builder.build_all(ORIGIN, get_count, get_owner, function()
			mod_storage:set_string(BUILT_KEY, VERSION)
			ready = true
			core.log("action", "[lep_lobby] built the hall at "
				.. core.pos_to_string(ORIGIN) .. " with " .. book:count() .. " rooms")
			local callbacks = waiting
			waiting = {}
			for _, waiting_callback in ipairs(callbacks) do
				waiting_callback()
			end
			if callback then
				callback()
			end
		end)
	end)
end

-- Calls callback() as soon as the hall exists.
local function when_ready(callback)
	if ready then
		callback()
	else
		waiting[#waiting + 1] = callback
	end
end

core.register_on_mods_loaded(function()
	if not ready then
		-- The map is available one step after startup.
		core.after(0, build)
	end
end)

--- Returns the important spots of the hall: spawn, portal, corridors,
-- protect_min, protect_max. See src/hall.lua and game/generated_hall.lua.
function lep_lobby.get_anchors()
	return anchors
end

--- Returns true if the position is inside the protected lobby area:
-- the hall, the corridors or the personal rooms.
function lep_lobby.is_inside(pos)
	local min, max = anchors.protect_min, anchors.protect_max
	if pos.x >= min.x and pos.x <= max.x
			and pos.y >= min.y and pos.y <= max.y
			and pos.z >= min.z and pos.z <= max.z then
		return true
	end
	local rel = vector.subtract(vector.round(pos), ORIGIN)
	for direction = 1, corridors.DIRECTIONS do
		local rel_min, rel_max = corridors.bounds(direction, book:count())
		if rel.x >= rel_min.x and rel.x <= rel_max.x
				and rel.y >= rel_min.y and rel.y <= rel_max.y
				and rel.z >= rel_min.z and rel.z <= rel_max.z then
			return true
		end
	end
	return false
end

--- Returns the personal room of a player, or nil if they have none:
-- a table with owner, slot, entrance, look_dir, door, sign, interior_min,
-- interior_max, portal and chest in world coordinates. See
-- src/corridors.lua.
function lep_lobby.get_room(player_name)
	local slot = book:get(player_name)
	if not slot then
		return nil
	end
	local room = corridors.room(slot)
	return {
		owner = player_name,
		slot = slot,
		entrance = vector.add(ORIGIN, room.entrance),
		look_dir = room.look_dir,
		door = vector.add(ORIGIN, room.door),
		sign = vector.add(ORIGIN, room.sign),
		interior_min = vector.add(ORIGIN, room.interior_min),
		interior_max = vector.add(ORIGIN, room.interior_max),
		portal = vector.add(ORIGIN, room.portal),
		chest = vector.add(ORIGIN, room.chest),
	}
end

--- Makes sure a player has a personal room and that it is built.
-- callback(room) is optional, room as in lep_lobby.get_room.
function lep_lobby.ensure_room(player_name, callback)
	callback = callback or function() end
	local slot, is_new = book:assign(player_name)
	if not is_new then
		callback(lep_lobby.get_room(player_name))
		return
	end

	mod_storage:set_string(BOOK_KEY, core.serialize(book:export()))
	local function finish()
		core.log("action", "[lep_lobby] built room " .. slot .. " for " .. player_name)
		callback(lep_lobby.get_room(player_name))
	end
	if ready then
		local direction = corridors.slot_position(slot)
		builder.build(ORIGIN, direction, get_count, get_owner, finish)
	else
		-- The pending build of the whole lobby includes the new room.
		waiting[#waiting + 1] = finish
	end
end

--- Brings an online player in front of a personal room, by default their
-- own. callback(ok, err) is optional.
function lep_lobby.enter_room(player_name, owner_name, callback)
	callback = callback or function() end
	owner_name = owner_name or player_name
	local room = lep_lobby.get_room(owner_name)
	if not room then
		callback(false, "player '" .. owner_name .. "' has no room")
		return
	end
	local ok, err = lep_places.move(player_name, PLACE, room.entrance)
	if ok then
		local player = core.get_player_by_name(player_name)
		player:set_look_horizontal(math.atan2(-room.look_dir.x, room.look_dir.z))
		player:set_look_vertical(0)
	end
	callback(ok, err)
end

--- Brings an online player into the hall. callback(ok, err) is optional.
function lep_lobby.enter(player_name, callback)
	callback = callback or function() end
	when_ready(function()
		callback(lep_places.move(player_name, PLACE))
	end)
end

--- Builds the hall again from scratch. callback() is optional.
function lep_lobby.rebuild(callback)
	ready = false
	build(function()
		-- Put everyone in the lobby back on the spawn point.
		for _, player in ipairs(core.get_connected_players()) do
			local name = player:get_player_name()
			if lep_places.get_place(name) == PLACE then
				lep_places.move(name, PLACE, anchors.spawn)
			end
		end
		if callback then
			callback()
		end
	end)
end
