-- Public API of lep_lobby and the building of the hall.

local load = lep_core.loader("lep_lobby")
local provider = load("game/generated_hall")

-- The hall hangs below the room layers, off the room grid, so no learning
-- room is ever directly above it.
local ORIGIN = { x = 256, y = 9000, z = 256 }
local PLACE = "lep_lobby:lobby"
local BUILT_KEY = "hall_built_version"

local mod_storage = core.get_mod_storage()
local anchors = provider.anchors(ORIGIN)
local ready = mod_storage:get_int(BUILT_KEY) == provider.version
local waiting = {}

lep_lobby.PLACE = PLACE

lep_places.register_place(PLACE, { default_pos = anchors.spawn })

local function build(callback)
	provider.build(ORIGIN, function()
		mod_storage:set_int(BUILT_KEY, provider.version)
		ready = true
		core.log("action", "[lep_lobby] built the hall at "
			.. core.pos_to_string(ORIGIN))
		local callbacks = waiting
		waiting = {}
		for _, waiting_callback in ipairs(callbacks) do
			waiting_callback()
		end
		if callback then
			callback()
		end
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

--- Returns the important spots of the hall: spawn, portal, corridor_start,
-- corridor_dir, protect_min, protect_max. See src/hall.lua.
function lep_lobby.get_anchors()
	return anchors
end

--- Returns true if the position is inside the protected lobby area.
function lep_lobby.is_inside(pos)
	local min, max = anchors.protect_min, anchors.protect_max
	return pos.x >= min.x and pos.x <= max.x
		and pos.y >= min.y and pos.y <= max.y
		and pos.z >= min.z and pos.z <= max.z
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
