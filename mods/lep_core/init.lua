-- LEP Core: shared helpers for all Luanti Education Platform mods.

local modpath = core.get_modpath("lep_core")
local loader = dofile(modpath .. "/src/loader.lua")
local loaders = loader.new_set(core.get_modpath)
local load = loaders("lep_core")

lep_core = {}

--- Returns the load function of the given mod. Every file of a mod is
-- loaded only once, from wherever it is requested.
-- Usage in any file of another mod:
--   local load = lep_core.loader("lep_example")
--   local api = load("src/api")
function lep_core.loader(modname)
	return loaders(modname)
end

--- Event dispatcher factory, see src/events.lua.
lep_core.events = load("src/events")

--- Formspec builder, see src/formspec.lua. Every LEP window uses it.
lep_core.formspec = load("src/formspec")

--- Protocols: append-only files in the world folder, see
-- game/protocols.lua.
lep_core.protocols = load("game/protocols")

local forgetting = load("src/forgetting").new(function(account, err)
	core.log("error", "[lep_core] a mod could not delete the data of " .. account
		.. ": " .. tostring(err))
end)

--- Registers a function(account) that deletes everything a mod keeps
-- about an account. It is called when an account is removed on request,
-- see the concept, section 12: the account still exists then and its
-- player is not in the game. A function that raises an error stops the
-- removal, so nothing is reported as deleted that is still there. It
-- has to cope with being called twice for the same account.
function lep_core.register_on_forget_account(listener)
	forgetting:register(listener)
end

--- Has every mod delete what it keeps about an account. Only
-- lep_accounts calls this, as one step of removing the account.
-- @return number of mods that failed
function lep_core.forget_account(account)
	assert(type(account) == "string" and account ~= "", "forget_account: account is missing")
	return forgetting:run(account)
end

-- Text for signs the server sets up itself. Needs the mod signs_lib when
-- it is used.
lep_core.signs = load("game/signs")

core.log("action", "[lep_core] loaded")
