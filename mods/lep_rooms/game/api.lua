-- Public API of lep_rooms.

local load = lep_core.loader("lep_rooms")
local rooms = load("src/rooms")
local build = load("game/build")
local holds = load("src/holds").new()
local S = core.get_translator("lep_rooms")

local STORAGE_KEY = "book"
-- Pause between two rooms when many are built in a row.
local BUILD_INTERVAL = 0.3

local mod_storage = core.get_mod_storage()
local types = rooms.new_types()
local book = rooms.new_book(core.parse_json(mod_storage:get_string(STORAGE_KEY), nil, true))
local on_build_callbacks = {}
-- Set of the place ids that are learning rooms.
local room_places = {}

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_rooms] callback for '" .. event_name
		.. "' failed: " .. tostring(err))
end)

local function save()
	mod_storage:set_string(STORAGE_KEY, core.write_json(book:export()))
end

local function place_id(type_id)
	return "room:" .. type_id
end

lep_rooms.PITCH = rooms.PITCH
lep_rooms.AIR = "lep_rooms:air"

-- Used by game/protection.lua.
lep_rooms._types = types
lep_rooms._book = book
lep_rooms._rooms = rooms

-- ---------------------------------------------------------------------------
-- Room types
-- ---------------------------------------------------------------------------

--- Registers a room type.
-- @param type_id Unique id, e.g. "lep_tz:room".
-- @param def Table with:
--   layer       integer, unique, must never change (height of the rooms)
--   size        interior size { x, y, z }
--   version     integer, default 1; raise it to have rooms rebuilt
--   privileges  set of privileges granted inside the room
--   on_build    optional function(owner, geometry) called after a room was
--               built or rebuilt, to furnish it
--   title       optional name of the room for people, see lep_places
--   prebuild    optional, false if rooms of this type are not built ahead
--               when accounts are created
function lep_rooms.register_type(type_id, def)
	types:register(type_id, def)
	on_build_callbacks[type_id] = def.on_build
	room_places[place_id(type_id)] = true
	lep_places.register_place(place_id(type_id), {
		inventory = lep_places.INVENTORY_LEARNING,
		privileges = def.privileges,
		title = def.title,
	})
end

--- Returns the ids of all room types, sorted.
function lep_rooms.get_types()
	return types:ids()
end

--- Returns the lep_places place id of a room type.
function lep_rooms.get_place_id(type_id)
	return place_id(type_id)
end

-- ---------------------------------------------------------------------------
-- Rooms
-- ---------------------------------------------------------------------------

--- Returns the geometry of a player's room, or nil if none is assigned.
-- See src/rooms.lua for the fields.
function lep_rooms.get_geometry(owner, type_id)
	local def = types:get(type_id)
	local record = def and book:get(type_id, owner)
	if not record then
		return nil
	end
	return rooms.geometry(def, record.slot)
end

--- Returns the room type and owner of the room a player is in, or nil.
function lep_rooms.get_current_room(player_name)
	local player = core.get_player_by_name(player_name)
	if not player then
		return nil
	end
	local where = rooms.locate(types, book, vector.round(player:get_pos()))
	if not where or where.part ~= "interior" then
		return nil
	end
	return where.type_id, where.owner
end

-- Builds one room and furnishes it. callback(ok, err)
local function build_room(owner, type_id, is_rebuild, callback)
	local def = types:get(type_id)
	if not def then
		callback(false, "unknown room type '" .. tostring(type_id) .. "'")
		return
	end
	local record, err = book:assign(type_id, owner)
	if not record then
		callback(false, err)
		return
	end
	save()

	local geometry = rooms.geometry(def, record.slot)
	build.room(geometry, function()
		local on_build = on_build_callbacks[type_id]
		if on_build then
			local ok, build_err = pcall(on_build, owner, geometry)
			if not ok then
				core.log("error", "[lep_rooms] on_build of '" .. type_id
					.. "' failed: " .. tostring(build_err))
			end
		end
		book:mark_built(type_id, owner, def.version)
		save()
		core.log("action", "[lep_rooms] built room '" .. type_id .. "' for " .. owner
			.. " at " .. core.pos_to_string(geometry.spawn))
		dispatcher:emit("room_built", owner, type_id, geometry, is_rebuild)
		callback(true)
	end)
end

--- Makes sure a room exists and is up to date. callback(ok, err)
function lep_rooms.ensure(owner, type_id, callback)
	local def = types:get(type_id)
	if not def then
		callback(false, "unknown room type '" .. tostring(type_id) .. "'")
		return
	end
	if not book:needs_build(type_id, owner, def.version) then
		callback(true)
		return
	end
	local record = book:get(type_id, owner)
	build_room(owner, type_id, record ~= nil and record.built_version ~= nil, callback)
end

--- Brings an online player into their own room of the given type.
-- Builds the room first if needed. callback(ok, err) is optional.
function lep_rooms.enter(player_name, type_id, callback)
	callback = callback or function() end
	lep_rooms.ensure(player_name, type_id, function(ok, err)
		if not ok then
			callback(false, err)
			return
		end
		local geometry = lep_rooms.get_geometry(player_name, type_id)
		callback(lep_places.move(player_name, place_id(type_id), geometry.spawn))
	end)
end

--- Brings an online player out of a room, back to where they came from.
-- A player who is held (see lep_rooms.hold) stays and is told why, unless
-- `force` is true. Leaving ends the hold.
-- @return true  or  false, error message
function lep_rooms.leave(player_name, force)
	if holds:is_held(player_name) and not force then
		core.chat_send_player(player_name, S("Your teacher has sent you here. "
			.. "You can leave the room when your teacher brings you back."))
		return false, "player is held"
	end
	if not force then
		-- Leaving is the player's own wish, so the rules for that apply.
		local ok, message = lep_places.may_go(player_name,
			lep_places.get_back_place(player_name))
		if not ok then
			if message then
				core.chat_send_player(player_name, message)
			end
			return false, "not allowed"
		end
	end
	return lep_places.move_back(player_name)
end

--- Holds a player in the learning room they are in: they cannot leave it
-- on their own. The hold ends when the player leaves the room in any
-- way, with lep_rooms.release, and with a restart of the server.
-- @return true, or false if the player is in no room or already held
function lep_rooms.hold(player_name)
	if not lep_rooms.get_current_room(player_name) then
		return false
	end
	local changed = holds:hold(player_name)
	if changed then
		dispatcher:emit("hold_changed", player_name, true)
	end
	return changed
end

--- Ends the hold of a player. Returns true if the player was held.
function lep_rooms.release(player_name)
	local changed = holds:release(player_name)
	if changed then
		dispatcher:emit("hold_changed", player_name, false)
	end
	return changed
end

--- Ends all holds. Returns the names of the players who were held.
function lep_rooms.release_all()
	local names = holds:release_all()
	for _, name in ipairs(names) do
		dispatcher:emit("hold_changed", name, false)
	end
	return names
end

--- Returns true if a player is held in a learning room.
function lep_rooms.is_held(player_name)
	return holds:is_held(player_name)
end

--- Registers a function(player_name, is_held) that is called when a
-- player is held or released.
lep_rooms.register_on_hold_changed = dispatcher:registrar("hold_changed")

-- Whoever leaves the learning rooms, in whatever way, is no longer held.
lep_places.register_on_place_changed(function(player_name, _, new_place)
	if not room_places[new_place] then
		lep_rooms.release(player_name)
	end
end)

--- Empties the interior of a room and keeps the shell. callback(ok, err)
function lep_rooms.clear_interior(owner, type_id, callback)
	callback = callback or function() end
	local geometry = lep_rooms.get_geometry(owner, type_id)
	if not geometry then
		callback(false, "no room of type '" .. tostring(type_id) .. "' for " .. owner)
		return
	end
	build.clear_interior(geometry, function()
		callback(true)
	end)
end

-- Puts players standing in a room back on its spawn point.
local function reset_occupants(type_id, owner, geometry)
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local current_type, current_owner = lep_rooms.get_current_room(name)
		if current_type == type_id and current_owner == owner then
			if lep_places.get_place(name) == place_id(type_id) then
				lep_places.move(name, place_id(type_id), geometry.spawn)
			else
				player:set_pos(geometry.spawn)
			end
		end
	end
end

--- Builds a room from scratch: new shell, empty interior, furnished again.
-- Whatever was built inside is lost. callback(ok, err) is optional.
function lep_rooms.rebuild(owner, type_id, callback)
	callback = callback or function() end
	if not book:get(type_id, owner) then
		callback(false, "no room of type '" .. tostring(type_id) .. "' for " .. owner)
		return
	end
	build_room(owner, type_id, true, function(ok, err)
		if ok then
			reset_occupants(type_id, owner, lep_rooms.get_geometry(owner, type_id))
		end
		callback(ok, err)
	end)
end

-- Runs jobs one after the other with a pause, so the server stays responsive.
-- callback(done, failed)
local function run_queue(jobs, callback)
	local done, failed = 0, 0
	local function step(index)
		local job = jobs[index]
		if not job then
			callback(done, failed)
			return
		end
		job(function(ok)
			if ok then
				done = done + 1
			else
				failed = failed + 1
			end
			core.after(BUILD_INTERVAL, step, index + 1)
		end)
	end
	step(1)
end

--- Rebuilds all rooms of one type, or of all types if type_id is nil.
-- callback(done, failed) is optional.
function lep_rooms.rebuild_all(type_id, callback)
	callback = callback or function() end
	local type_ids = type_id and { type_id } or types:ids()
	local jobs = {}
	for _, id in ipairs(type_ids) do
		for _, owner in ipairs(book:owners(id)) do
			jobs[#jobs + 1] = function(job_done)
				lep_rooms.rebuild(owner, id, job_done)
			end
		end
	end
	run_queue(jobs, callback)
end

--- Builds rooms ahead of time, so a whole class can enter at once.
-- @param owners List of player names. They do not have to be online.
-- callback(done, failed) is optional.
function lep_rooms.prebuild(owners, type_id, callback)
	callback = callback or function() end
	local jobs = {}
	for _, owner in ipairs(owners) do
		jobs[#jobs + 1] = function(job_done)
			lep_rooms.ensure(owner, type_id, job_done)
		end
	end
	run_queue(jobs, callback)
end

--- Builds the rooms of all types that are built ahead, for a list of
-- owners: everything a new student needs, so that a whole class can
-- start at once. Rooms that exist are left alone. The rooms are built
-- one after the other, with a pause in between, so the server stays
-- playable.
-- @param owners List of player names. They do not have to be online.
-- callback(done, failed) is optional.
function lep_rooms.prebuild_all(owners, callback)
	callback = callback or function() end
	local jobs = {}
	for _, type_id in ipairs(types:prebuild_ids()) do
		for _, owner in ipairs(owners) do
			jobs[#jobs + 1] = function(job_done)
				lep_rooms.ensure(owner, type_id, job_done)
			end
		end
	end
	run_queue(jobs, callback)
end

--- Registers a function(owner, type_id, geometry, is_rebuild) that is called
-- after a room was built. On a rebuild everything inside was lost.
lep_rooms.register_on_room_built = dispatcher:registrar("room_built")
