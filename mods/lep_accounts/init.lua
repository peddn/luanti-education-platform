-- LEP Accounts: who may enter this world, and the two things that are
-- done to accounts from outside: creating them and setting a password.

local load = lep_core.loader(core.get_current_modname())

lep_accounts = {}

load("game/api")
load("game/door")

core.log("action", "[lep_accounts] loaded")
