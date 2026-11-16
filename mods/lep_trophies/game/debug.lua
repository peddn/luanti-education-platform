-- Debug helpers. Only loaded when the setting "lep_debug" is true.

local load = lep_core.loader("lep_trophies")
local trophies = load("src/trophies")

if not core.registered_privileges.lep_debug then
	core.register_privilege("lep_debug", {
		description = "Can use LEP debug commands",
		give_to_singleplayer = false,
	})
end

-- Two trophies that do not depend on any learning module.
lep_trophies.register_trophy("lep_trophies:debug_bronze", {
	title = "Testpokal Bronze",
	description = "Vergeben mit /lep_trophy.",
})
lep_trophies.register_trophy("lep_trophies:debug_gold", {
	title = "Testpokal Gold",
	description = "Vergeben mit /lep_trophy.",
	material = lep_trophies.GOLD,
})

core.register_chatcommand("lep_trophy", {
	params = "bronze | gold | daily <count>",
	description = "Give yourself a test trophy, or add to your counter of solved "
		.. "daily tasks",
	privs = { lep_debug = true },
	func = function(name, param)
		local action, amount = param:match("^%s*(%S*)%s*(%S*)")
		if action == "bronze" or action == "gold" then
			local is_new = lep_trophies.award(name, "lep_trophies:debug_" .. action)
			return true, is_new and "Awarded." or "You already have it."
		elseif action == "daily" and tonumber(amount) and tonumber(amount) >= 1 then
			lep_trophies._count(name, trophies.DAILY_COUNTER, math.floor(tonumber(amount)),
				trophies.DAILY_STEPS, trophies.daily_id)
			return true, "Counter of daily tasks is now "
				.. lep_trophies._get_state(name).counters[trophies.DAILY_COUNTER] .. "."
		end
		return false, "Usage: /lep_trophy bronze | gold | daily <count>"
	end,
})
