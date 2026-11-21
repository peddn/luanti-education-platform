-- The world is closed. Who comes with a name that has no account is
-- turned away: accounts are created on order, not by walking in. That
-- goes for the admin as well: the world creates that account by itself,
-- with a start password (game/admin.lua).

local load = lep_core.loader("lep_accounts")
local accounts = load("src/accounts")
local S = core.get_translator("lep_accounts")

local MESSAGE = S("There is no account with this name. You get your access from your teacher.")

core.register_on_prejoinplayer(function(name)
	if core.is_singleplayer() then
		return nil
	end
	if lep_accounts.is_being_removed(name) then
		-- Nobody comes in under a name while its account is taken apart.
		return core.get_translated_string("de", MESSAGE)
	end
	if accounts.may_join(lep_accounts.exists(name)) then
		return nil
	end
	core.log("action", "[lep_accounts] turned away '" .. tostring(name)
		.. "': there is no such account")
	-- Nobody is in the game yet whose language could be asked for.
	return core.get_translated_string("de", MESSAGE)
end)
