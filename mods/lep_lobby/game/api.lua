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

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_lobby] callback for " .. event_name .. " failed: " .. tostring(err))
end)

lep_lobby.PLACE = PLACE

lep_places.register_place(PLACE, { default_pos = anchors.spawn, title = "Lobby" })

local function get_count()
	return book:count()
end

local function get_owner(slot)
	return book:owner(slot)
end

-- Tells other mods about every room of one corridor, or of all corridors.
-- Building a corridor rewrites all its rooms, so whatever other mods put
-- into them has to be set again.
local function announce_rooms(direction)
	for slot = 0, book:count() - 1 do
		-- A room whose owner was removed stands empty.
		local owner = book:owner(slot)
		if owner and (not direction or corridors.slot_position(slot) == direction) then
			dispatcher:emit("room_built", lep_lobby.get_room(owner))
		end
	end
end

local function build(callback)
	provider.build(ORIGIN, function()
		-- The hall closes its wall again, so the corridors come after it.
		builder.build_all(ORIGIN, get_count, get_owner, function()
			mod_storage:set_string(BUILT_KEY, VERSION)
			ready = true
			core.log("action", "[lep_lobby] built the hall at "
				.. core.pos_to_string(ORIGIN) .. " with " .. book:count() .. " rooms")
			dispatcher:emit("hall_built", anchors)
			announce_rooms(nil)
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

--- Calls callback() as soon as hall, corridors and rooms exist.
function lep_lobby.when_ready(callback)
	if ready then
		callback()
	else
		waiting[#waiting + 1] = callback
	end
end

local when_ready = lep_lobby.when_ready

--- Registers a function(anchors) that is called whenever the hall has
-- been built or rebuilt. Anchors as in lep_lobby.get_anchors.
lep_lobby.register_on_hall_built = dispatcher:registrar("hall_built")

--- Registers a function(room) that is called whenever a personal room has
-- been built or rebuilt. Room as in lep_lobby.get_room. Everything inside
-- the room is gone at that moment and has to be set again.
lep_lobby.register_on_room_built = dispatcher:registrar("room_built")

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
-- interior_max, portal, chest and pedestals in world coordinates. See
-- src/corridors.lua.
function lep_lobby.get_room(player_name)
	local slot = book:get(player_name)
	if not slot then
		return nil
	end
	local room = corridors.room(slot)
	local pedestals = {}
	for index, spot in ipairs(room.pedestals) do
		pedestals[index] = vector.add(ORIGIN, spot)
	end
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
		pedestals = pedestals,
	}
end

--- Returns the personal rooms of all players, as in lep_lobby.get_room.
function lep_lobby.get_rooms()
	local rooms = {}
	for slot = 0, book:count() - 1 do
		rooms[#rooms + 1] = lep_lobby.get_room(book:owner(slot))
	end
	return rooms
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
		-- Worded like the message of lep_rooms, so a log reads as one list.
		local room = lep_lobby.get_room(player_name)
		core.log("action", "[lep_lobby] built room 'lep_lobby:room' for " .. player_name
			.. " at " .. core.pos_to_string(room.entrance) .. ", slot " .. slot)
		callback(room)
	end
	if ready then
		local direction = corridors.slot_position(slot)
		builder.build(ORIGIN, direction, get_count, get_owner, function()
			announce_rooms(direction)
			finish()
		end)
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

-- Display names. The sign of a room shows the display name of its owner,
-- and the owner chooses the name there.
if core.global_exists("lep_accounts") then
	lep_accounts.register_on_display_name_changed(function(account)
		local room = lep_lobby.get_room(account)
		if not room then
			return
		end
		-- The owner may be far away or not in the game: the name can be
		-- taken away from outside.
		core.load_area(room.sign)
		if core.get_node(room.sign).name == "lep_lobby:room_sign" then
			lep_core.signs.write(room.sign, builder.sign_text(account))
		end
	end)
end

-- An account that is removed gives its room back. The room is built
-- again empty, with a blank sign, and waits for the next new player.
lep_core.register_on_forget_account(function(account)
	local room = lep_lobby.get_room(account)
	if not room then
		return
	end
	book:release(account)
	mod_storage:set_string(BOOK_KEY, core.serialize(book:export()))
	core.log("action", "[lep_lobby] room in slot " .. room.slot .. " is free again")
	if not ready then
		-- The pending build of the whole lobby writes the room empty.
		return
	end
	local direction = corridors.slot_position(room.slot)
	builder.build(ORIGIN, direction, get_count, get_owner, function()
		-- Writing the corridor leaves the metadata of what stood in the
		-- room: chest, pedestals and portal carry the name of the owner.
		for _, pos in ipairs(core.find_nodes_with_meta(
				vector.offset(room.interior_min, -1, -1, -1),
				vector.offset(room.interior_max, 1, 1, 1))) do
			if not vector.equals(pos, room.sign) and not vector.equals(pos, room.door) then
				core.remove_node(pos)
			end
		end
		announce_rooms(direction)
	end)
end)

-- A click on a name sign. Only the sign of the own room does something.
function lep_lobby._on_sign_click(pos, player_name)
	if not core.global_exists("lep_accounts") then
		return
	end
	local room = lep_lobby.get_room(player_name)
	if room and vector.equals(room.sign, pos) then
		lep_accounts.show_name_window(player_name)
	end
end
