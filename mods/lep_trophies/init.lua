-- LEP Trophies: awards trophies for milestones and lets players show
-- them on the pedestals in their room.

local load = lep_core.loader(core.get_current_modname())

lep_trophies = {}

load("game/nodes")
load("game/api")
load("game/milestones")
load("game/pedestals")
load("game/commands")

if core.settings:get_bool("lep_debug", false) then
	load("game/debug")
end

core.log("action", "[lep_trophies] loaded")
