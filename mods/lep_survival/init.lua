-- LEP Survival: rules of the survival world.

local load = lep_core.loader(core.get_current_modname())

load("game/recipes")

-- Achievements in survival become trophies, if both mods are there.
if core.get_modpath("awards") and core.get_modpath("lep_trophies") then
	load("game/achievements")
end

load("game/forget")

core.log("action", "[lep_survival] loaded")
