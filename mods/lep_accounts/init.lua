-- LEP Accounts: who may enter this world, the two things that are done
-- to accounts from outside, creating them and setting a password, and
-- the display names players choose.

local load = lep_core.loader(core.get_current_modname())

lep_accounts = {}

load("game/api")
load("game/door")
load("game/names")
load("game/show")
load("game/name_window")

if core.settings:get_bool("lep_debug", false) then
	load("game/debug")
end

core.log("action", "[lep_accounts] loaded")
