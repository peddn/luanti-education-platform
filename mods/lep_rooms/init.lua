-- LEP Rooms: builds and assigns personal learning rooms high above the world.

local load = lep_core.loader(core.get_current_modname())

lep_rooms = {}

load("game/nodes")
load("game/api")
load("game/protection")

if core.settings:get_bool("lep_debug", false) then
	load("game/debug")
end

core.log("action", "[lep_rooms] loaded")
