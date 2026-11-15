-- LEP Progress: takes results from the learning modules, keeps level and
-- workload per player and tells other mods what happened.

local load = lep_core.loader(core.get_current_modname())

lep_progress = {}

load("game/api")
load("game/commands")

if core.settings:get_bool("lep_debug", false) then
	load("game/debug")
end

core.log("action", "[lep_progress] loaded")
