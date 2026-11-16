-- Debug helpers. Only loaded when the setting "lep_debug" is true.

if not core.registered_privileges.lep_debug then
	core.register_privilege("lep_debug", {
		description = "Can use LEP debug commands",
		give_to_singleplayer = false,
	})
end

core.register_chatcommand("lep_rewards_reset", {
	params = "[<player>]",
	description = "Reset today's reward limit, as if a new day had begun. "
		.. "Without a player, your own.",
	privs = { lep_debug = true },
	func = function(name, param)
		local target = param:match("^%s*(%S+)") or name
		if not core.player_exists(target) then
			return false, "There is no player " .. target .. "."
		end
		lep_rewards.reset_allowance(target)
		local remaining, limits = lep_rewards.get_remaining(target)
		return true, "Reset. " .. target .. " has " .. remaining.task .. " of "
			.. limits.task .. " tasks and " .. remaining.chest .. " of "
			.. limits.chest .. " task chests left today."
	end,
})
