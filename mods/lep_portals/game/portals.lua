-- Builds, lights and runs the portals.

local load = lep_core.loader("lep_portals")
local frames = load("src/frames")
local links = load("src/links")
local S = core.get_translator("lep_portals")

local FIELD = "lep_portals:field"
local FIELD_INACTIVE = "lep_portals:field_inactive"
local FRAME = "lep_portals:frame"
local PLATFORM = "lep_portals:platform"
local PLAYER_FRAME = "default:obsidian"
local IGNITER = "default:mese_crystal"

-- Seconds a player has to stand in a field before it takes effect.
local DWELL = 1
-- Seconds until a hint is repeated for a player who keeps standing there.
local HINT_PAUSE = 6
-- Raise this when the portals in the lobby change, so they are set again.
local LOBBY_VERSION = 1

local storage = core.get_mod_storage()
local plots = links.new_plots(core.deserialize(storage:get_string("plots")))
local wilderness = core.deserialize(storage:get_string("wilderness"))

local function save_plots()
	storage:set_string("plots", core.serialize(plots:export()))
end

local function load_around(pos)
	core.load_area(vector.offset(pos, -2, -2, -2), vector.offset(pos, 2, 3, 2))
end

--------------------------------------------------------------------------
-- Setting nodes

local function set_field(base, axis, active, kind, owner)
	for _, pos in ipairs(frames.field(base, axis)) do
		core.set_node(pos, {
			name = active and FIELD or FIELD_INACTIVE,
			param2 = axis == "x" and 0 or 1,
		})
		local meta = core.get_meta(pos)
		meta:set_string("kind", kind)
		meta:set_string("owner", owner or "")
		meta:mark_as_private({ "kind", "owner" })
	end
end

local function remove_field(base, axis, owner)
	for _, pos in ipairs(frames.field(base, axis)) do
		if core.get_node(pos).name == FIELD
				and core.get_meta(pos):get_string("owner") == owner then
			core.remove_node(pos)
		end
	end
end

local function set_frame(base, axis)
	for _, list in ipairs({ frames.required(base, axis), frames.corners(base, axis) }) do
		for _, pos in ipairs(list) do
			core.set_node(pos, { name = FRAME })
		end
	end
end

--------------------------------------------------------------------------
-- Portals in the lobby

local function hall_base()
	return lep_lobby.get_anchors().portal
end

local function room_axis(room)
	-- Players walk into the room along look_dir, the frame stands across.
	return room.look_dir.x ~= 0 and "z" or "x"
end

local function set_hall_portal()
	local base = hall_base()
	load_around(base)
	set_frame(base, "x")
	set_field(base, "x", true, links.LOBBY)
end

local function set_room_portal(room)
	local axis = room_axis(room)
	load_around(room.portal)
	set_frame(room.portal, axis)
	set_field(room.portal, axis, plots:get(room.owner) ~= nil, links.ROOM, room.owner)
end

local function update_room_field(owner)
	local room = lep_lobby.get_room(owner)
	if room then
		load_around(room.portal)
		set_field(room.portal, room_axis(room), plots:get(owner) ~= nil, links.ROOM, owner)
	end
end

lep_lobby.register_on_hall_built(set_hall_portal)
lep_lobby.register_on_room_built(set_room_portal)

-- A lobby that was built before this mod existed, or before its portals
-- changed, gets them now.
core.register_on_mods_loaded(function()
	if storage:get_int("lobby_version") == LOBBY_VERSION then
		return
	end
	core.after(0, function()
		lep_lobby.when_ready(function()
			set_hall_portal()
			for _, room in ipairs(lep_lobby.get_rooms()) do
				set_room_portal(room)
			end
			storage:set_int("lobby_version", LOBBY_VERSION)
		end)
	end)
end)

--------------------------------------------------------------------------
-- Fixed portal in the wilderness

local PLATFORM_RADIUS = 2

-- Returns a place with solid ground near the start of the world.
local function find_wilderness_spot()
	local static = core.setting_get_pos("static_spawnpoint")
	if static then
		return vector.round(static)
	end
	for ring = 0, 12 do
		local distance = ring * 16
		for _, dir in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
			local x, z = dir[1] * distance, dir[2] * distance
			local y = core.get_spawn_level(x, z)
			if y then
				return { x = x, y = y, z = z }
			end
			if ring == 0 then
				break
			end
		end
	end
	-- No suitable ground found: a platform in the air above the origin.
	return { x = 0, y = 30, z = 0 }
end

local function build_wilderness_portal()
	local base = find_wilderness_spot()
	local r = PLATFORM_RADIUS
	local min = vector.offset(base, -r, -1, -r)
	local max = vector.offset(base, r, 4, r)

	core.emerge_area(min, max, function(_, _, remaining)
		if remaining > 0 then
			return
		end
		for x = min.x, max.x do
			for z = min.z, max.z do
				core.set_node({ x = x, y = min.y, z = z }, { name = PLATFORM })
				for y = min.y + 1, max.y do
					core.remove_node({ x = x, y = y, z = z })
				end
			end
		end
		set_frame(base, "x")
		set_field(base, "x", true, links.WILDERNESS)

		wilderness = {
			base = base,
			arrival = frames.arrival(base, "x", 1),
			min = min,
			max = max,
		}
		storage:set_string("wilderness", core.serialize(wilderness))
		core.log("action", "[lep_portals] built the wilderness portal at "
			.. core.pos_to_string(base))
	end)
end

core.register_on_mods_loaded(function()
	if not wilderness then
		core.after(0, build_wilderness_portal)
	end
end)

-- Nobody may change the platform or build into it.
local old_is_protected = core.is_protected

function core.is_protected(pos, name)
	if wilderness
			and pos.x >= wilderness.min.x and pos.x <= wilderness.max.x
			and pos.y >= wilderness.min.y and pos.y <= wilderness.max.y
			and pos.z >= wilderness.min.z and pos.z <= wilderness.max.z then
		return true
	end
	return old_is_protected(pos, name)
end

--------------------------------------------------------------------------
-- Portals that players build

local function is_player_frame(pos)
	return core.get_node(pos).name == PLAYER_FRAME
end

local function is_free(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def ~= nil and def.buildable_to == true
end

local function extinguish(owner)
	local plot = plots:remove(owner)
	if not plot then
		return
	end
	save_plots()
	load_around(plot.base)
	remove_field(plot.base, plot.axis, owner)
	update_room_field(owner)
	if core.get_player_by_name(owner) then
		core.chat_send_player(owner, S("Your portal has gone out."))
	end
	core.log("action", "[lep_portals] portal of " .. owner .. " at "
		.. core.pos_to_string(plot.base) .. " went out")
end

-- Tries to light the frame that the node at `clicked` belongs to.
-- @return true if a portal was lit
local function light(player, clicked)
	local name = player:get_player_name()

	local base, axis = frames.find(clicked, is_player_frame, is_free)
	if not base then
		if axis == frames.BLOCKED then
			core.chat_send_player(name, S("The inside of the frame must be empty."))
		else
			core.chat_send_player(name, S("This is not a complete portal frame: "
				.. "3 wide and 4 high, upright, with 1 x 2 free inside."))
		end
		return false
	end

	if lep_places.get_place(name) ~= lep_places.WILDERNESS then
		core.chat_send_player(name, S("You can only light a portal in the wilderness."))
		return false
	end

	-- Own plot: somebody protects this spot, and this player may build there.
	-- Asked through the engine, so the protection mod stays replaceable.
	for _, pos in ipairs(frames.field(base, axis)) do
		if core.is_protected(pos, name) or not core.is_protected(pos, "") then
			core.chat_send_player(name,
				S("You can only light a portal on your own protected plot."))
			return false
		end
	end

	local side = frames.side_of(base, axis, player:get_pos())
	local old = plots:set(name, base, axis, frames.arrival(base, axis, side))
	save_plots()
	if old then
		load_around(old.base)
		remove_field(old.base, old.axis, name)
	end
	set_field(base, axis, true, links.PLOT, name)
	update_room_field(name)

	core.chat_send_player(name, S("Your portal is lit. It leads to your room in the lobby."))
	core.log("action", "[lep_portals] " .. name .. " lit a portal at "
		.. core.pos_to_string(base))
	return true
end

local igniter_def = core.registered_items[IGNITER]
local old_on_place = igniter_def and igniter_def.on_place or core.item_place

core.override_item(IGNITER, {
	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type == "node" and placer and placer:is_player()
				and core.get_node(pointed_thing.under).name == PLAYER_FRAME then
			if light(placer, pointed_thing.under)
					and not core.is_creative_enabled(placer:get_player_name()) then
				itemstack:take_item()
			end
			return itemstack
		end
		return old_on_place(itemstack, placer, pointed_thing)
	end,
})

-- A portal goes out when its frame is broken.
core.register_on_dignode(function(pos, oldnode)
	if oldnode.name ~= PLAYER_FRAME then
		return
	end
	local fields = core.find_nodes_in_area(
		vector.offset(pos, -2, -2, -2), vector.offset(pos, 2, 2, 2), { FIELD })
	local owners = {}
	for _, field_pos in ipairs(fields) do
		local meta = core.get_meta(field_pos)
		if meta:get_string("kind") == links.PLOT then
			owners[meta:get_string("owner")] = true
		end
	end
	for owner in pairs(owners) do
		local plot = plots:get(owner)
		if plot and not frames.is_complete(plot.base, plot.axis, is_player_frame) then
			extinguish(owner)
		end
	end
end)

--------------------------------------------------------------------------
-- Using portals

local function face(player, dir)
	player:set_look_horizontal(math.atan2(-dir.x, dir.z))
	player:set_look_vertical(0)
end

-- The place a destination lies in.
local TARGET_PLACE = {
	[links.TO_WILDERNESS] = lep_places.WILDERNESS,
	[links.TO_PLOT] = lep_places.WILDERNESS,
	[links.TO_HALL] = lep_lobby.PLACE,
	[links.TO_ROOM] = lep_lobby.PLACE,
}

local function use(player, field_pos)
	local name = player:get_player_name()
	local meta = core.get_meta(field_pos)
	local owner = meta:get_string("owner")
	local destination = links.destination(
		meta:get_string("kind"), owner, name, plots:get(owner) ~= nil)

	-- Stepping into a portal is the player's own wish, so the rules for
	-- that apply. A class mode can close the wilderness this way.
	local target = TARGET_PLACE[destination]
	if target then
		local allowed, message = lep_places.may_go(name, target)
		if not allowed then
			if message then
				core.chat_send_player(name, message)
			end
			return false
		end
	end

	if destination == links.TO_WILDERNESS then
		if wilderness then
			-- A player who was taken out of the wilderness comes back to
			-- where they stood.
			lep_places.move(name, lep_places.WILDERNESS,
				lep_places.take_return(name, lep_places.WILDERNESS) or wilderness.arrival)
			face(player, { x = 0, z = 1 })
		end
	elseif destination == links.TO_HALL then
		lep_places.move(name, lep_lobby.PLACE, frames.arrival(hall_base(), "x", -1))
		face(player, { x = 0, z = -1 })
	elseif destination == links.TO_ROOM then
		local room = lep_lobby.get_room(name)
		if room then
			lep_places.move(name, lep_lobby.PLACE, {
				x = room.portal.x - room.look_dir.x,
				y = room.portal.y,
				z = room.portal.z - room.look_dir.z,
			})
			face(player, { x = -room.look_dir.x, z = -room.look_dir.z })
		end
	elseif destination == links.TO_PLOT then
		lep_places.move(name, lep_places.WILDERNESS, plots:get(name).arrival)
	elseif destination == links.HINT_BUILD then
		core.chat_send_player(name, S("This portal is not active yet. Build a frame of "
			.. "obsidian on your own protected plot, 3 wide and 4 high, and light it "
			.. "with a mese crystal."))
		return false
	elseif destination == links.HINT_FOREIGN then
		core.chat_send_player(name, S("This portal belongs to @1.", owner))
		return false
	end
	return true
end

local dwell = {}
local timer = 0

core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.25 then
		return
	end
	local elapsed = timer
	timer = 0

	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local pos = player:get_pos()
		local field_pos = vector.round({ x = pos.x, y = pos.y + 0.5, z = pos.z })
		local node_name = core.get_node(field_pos).name
		if node_name == FIELD or node_name == FIELD_INACTIVE then
			dwell[name] = (dwell[name] or 0) + elapsed
			if dwell[name] >= DWELL then
				if use(player, field_pos) then
					dwell[name] = nil
				else
					dwell[name] = -HINT_PAUSE
				end
			end
		else
			dwell[name] = nil
		end
	end
end)

core.register_on_leaveplayer(function(player)
	dwell[player:get_player_name()] = nil
end)
