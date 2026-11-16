-- LEP Rewards: pays rewards for solved tasks and completed levels, into
-- the reward chest in the player's room or straight into the inventory.

local load = lep_core.loader(core.get_current_modname())

lep_rewards = {}

load("game/api")
load("game/chest")
load("game/commands")

if core.settings:get_bool("lep_debug", false) then
	load("game/debug")
end

core.log("action", "[lep_rewards] loaded")
