-- The learning hall and the portals of the learning modules in it.

local load = lep_core.loader("lep_portals")
local frames = load("src/frames")
local learning = load("src/learning")
learning.use_frames(frames)
local links = load("src/links")
local setters = load("game/setters")
local S = core.get_translator("lep_portals")

-- The hall hangs this far above the lobby: out of sight, because the
-- server sends no map from that far away.
local HEIGHT_ABOVE_LOBBY = 256
local BUILT_KEY = "learning_built"
local SLOTS_KEY = "learning_slots"

local storage = core.get_mod_storage()
local slots = learning.new_slots(core.deserialize(storage:get_string(SLOTS_KEY)))

-- Registered modules by id: title, place, enter, field (node name), slot.
local modules = {}

local M = {}

-- The field of the portal in the lobby that leads here.
M.HUB_FIELD = lep_portals._register_field("hub", "#30c060")
setters.add_field_node(M.HUB_FIELD)

local function origin()
	local anchor = lep_lobby.get_anchors().portal
	return { x = anchor.x, y = anchor.y - 1 + HEIGHT_ABOVE_LOBBY, z = anchor.z }
end

-- Turns a portal of src/learning.lua into world coordinates.
local function in_world(portal)
	local base = origin()
	local signs = {}
	for index, sign in ipairs(portal.signs) do
		signs[index] = { pos = vector.add(base, sign.pos), wall = sign.wall }
	end
	return {
		base = vector.add(base, portal.base),
		axis = portal.axis,
		side = portal.side,
		arrival = vector.add(base, portal.arrival),
		look_dir = portal.look_dir,
		signs = signs,
	}
end

--- Returns the two portals in the lobby hall, see learning.hub.
function M.hub()
	return learning.hub(lep_lobby.get_anchors().portal)
end

--------------------------------------------------------------------------
-- Building

local function version()
	return learning.VERSION .. ":" .. slots:count()
end

local function set_module_portal(def)
	setters.set_portal(in_world(learning.portal(def.slot)), {
		kind = links.MODULE, owner = def.id, field = def.field, text = def.title,
	})
end

local function build(callback)
	local base = origin()
	local count = slots:count()
	local rel_min, rel_max = learning.bounds(count)
	local min, max = vector.add(base, rel_min), vector.add(base, rel_max)

	core.emerge_area(min, max, function(_, _, remaining)
		if remaining > 0 then
			return
		end
		local ids = {
			[learning.FLOOR] = core.get_content_id("lep_lobby:floor"),
			[learning.WALL] = core.get_content_id("lep_lobby:wall"),
			[learning.LAMP] = core.get_content_id("lep_lobby:lamp"),
			[learning.AIR] = core.CONTENT_AIR,
		}
		local vm = core.get_voxel_manip()
		local emin, emax = vm:read_from_map(min, max)
		local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
		local data = vm:get_data()
		for z = rel_min.z, rel_max.z do
			for y = rel_min.y, rel_max.y do
				for x = rel_min.x, rel_max.x do
					data[area:index(base.x + x, base.y + y, base.z + z)] =
						ids[learning.kind_at(x, y, z, count)]
				end
			end
		end
		vm:set_data(data)
		vm:write_to_map(true)

		setters.set_portal(in_world(learning.exit()), { kind = links.EXIT, text = S("Lobby") })
		for _, def in pairs(modules) do
			set_module_portal(def)
		end

		storage:set_string(BUILT_KEY, version())
		core.log("action", "[lep_portals] built the learning hall at "
			.. core.pos_to_string(base) .. " for " .. count .. " portals")
		if callback then
			callback()
		end
	end)
end

-- The hall is built when it is missing, when its shape changed, and when
-- a module was added.
core.register_on_mods_loaded(function()
	if storage:get_string(BUILT_KEY) ~= version() then
		core.after(0, build)
	end
end)

-- Nobody may change the learning hall.
local old_is_protected = core.is_protected

function core.is_protected(pos, name)
	local base = origin()
	local rel_min, rel_max = learning.bounds(slots:count())
	if pos.x >= base.x + rel_min.x and pos.x <= base.x + rel_max.x
			and pos.y >= base.y + rel_min.y and pos.y <= base.y + rel_max.y
			and pos.z >= base.z + rel_min.z and pos.z <= base.z + rel_max.z then
		return true
	end
	return old_is_protected(pos, name)
end

--------------------------------------------------------------------------
-- Modules

--- Gives a learning module a portal in the learning hall. The module does
-- not know where it stands; it keeps its place for good.
-- @param id Unique id, for example the id of the module.
-- @param def Table with:
--   title   what the sign above the portal says, translatable
--   colour  colour of the field, "#rrggbb"
--   place   id of the place the portal leads to, so the rules for moves
--           players make on their own can be asked
--   enter   function(player_name) that brings the player there
function lep_portals.register_learning_portal(id, def)
	assert(type(id) == "string" and id ~= "", "portal id must be a non-empty string")
	assert(not modules[id], "learning portal '" .. id .. "' already exists")
	assert(type(def) == "table" and type(def.title) == "string" and def.title ~= "",
		"learning portal needs a title")
	assert(type(def.colour) == "string" and def.colour:match("^#%x%x%x%x%x%x$"),
		"learning portal needs a colour like #ff9020")
	assert(type(def.place) == "string" and def.place ~= "", "learning portal needs a place")
	assert(type(def.enter) == "function", "learning portal needs an enter function")

	local field = lep_portals._register_field(id, def.colour)
	setters.add_field_node(field)
	local slot, is_new = slots:assign(id)
	if is_new then
		storage:set_string(SLOTS_KEY, core.serialize(slots:export()))
	end
	modules[id] = {
		id = id, title = def.title, place = def.place, enter = def.enter,
		field = field, slot = slot,
	}
	core.log("action", "[lep_portals] learning portal " .. id .. " has slot " .. slot)
end

--------------------------------------------------------------------------
-- Using

-- Per player: the id of the module they entered through its portal.
local entered = {}

--- Brings a player from the lobby hall into the learning hall.
-- @param callback Optional function(look_dir) called after the move.
function M.enter(player_name, callback)
	local exit = in_world(learning.exit())
	if lep_places.move(player_name, lep_lobby.PLACE, exit.arrival) and callback then
		callback(exit.look_dir)
	end
end

--- Brings a player through the portal of a module.
-- @return true if the player was moved
function M.enter_module(player_name, id)
	local def = modules[id]
	if not def then
		core.chat_send_player(player_name, S("This portal is out of order."))
		return false
	end
	local allowed, message = lep_places.may_go(player_name, def.place)
	if not allowed then
		if message then
			core.chat_send_player(player_name, message)
		end
		return false
	end
	entered[player_name] = id
	def.enter(player_name)
	return true
end

-- Whoever went in through a portal comes out in front of it, not at the
-- arrival point of the lobby.
lep_places.register_on_place_changed(function(player_name, old_place, new_place)
	local def = modules[entered[player_name] or ""]
	if not def or old_place ~= def.place then
		return
	end
	entered[player_name] = nil
	if new_place ~= lep_lobby.PLACE then
		return
	end
	local portal = in_world(learning.portal(def.slot))
	-- After the move that is just happening.
	core.after(0, function()
		local player = core.get_player_by_name(player_name)
		if player and lep_places.get_place(player_name) == lep_lobby.PLACE then
			lep_places.move(player_name, lep_lobby.PLACE, portal.arrival)
			player:set_look_horizontal(math.atan2(-portal.look_dir.x, portal.look_dir.z))
			player:set_look_vertical(0)
		end
	end)
end)

core.register_on_leaveplayer(function(player)
	entered[player:get_player_name()] = nil
end)

return M
