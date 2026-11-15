-- LEP Places: moves players between places and keeps position,
-- inventory and privileges consistent.

local load = lep_core.loader(core.get_current_modname())

lep_places = {}

load("game/api")

if core.settings:get_bool("lep_debug", false) then
	load("game/debug")
end

core.log("action", "[lep_places] loaded")
