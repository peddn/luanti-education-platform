-- Chat commands of lep_rewards.

local S = core.get_translator("lep_rewards")

core.register_privilege("lep_view_rewards", {
	description = "Can view the reward protocol of other players",
	give_to_singleplayer = false,
	give_to_admin = true,
})

core.register_chatcommand("lep_rewards", {
	description = S("Show what the rewards contain and how many you can still earn today"),
	func = function(name)
		local remaining, limits = lep_rewards.get_remaining(name)
		local lines = {
			S("Solved task: @1", lep_rewards.describe_items(
				lep_rewards.get_reward(lep_rewards.SMALL))),
			S("Task chest or completed level: @1", lep_rewards.describe_items(
				lep_rewards.get_reward(lep_rewards.MEDIUM))),
			S("Completed stage: @1", lep_rewards.describe_items(
				lep_rewards.get_reward(lep_rewards.LARGE))),
			S("Left today: @1 of @2 tasks, @3 of @4 task chests",
				remaining.task, limits.task, remaining.chest, limits.chest),
		}
		return true, table.concat(lines, "\n")
	end,
})

local REASONS = {
	task = S("task"),
	chest = S("task chest"),
	level = S("level completed"),
	stage = S("stage completed"),
}

core.register_chatcommand("lep_rewards_log", {
	params = "[<player>] [<count>]",
	description = S("Show the last rewards, your own or those of another player"),
	func = function(name, param)
		local first, second = param:match("^%s*(%S*)%s*(%S*)")
		local target, count = name, 10
		if tonumber(first) then
			count = tonumber(first)
		elseif first ~= "" then
			target = first
			count = tonumber(second) or count
		end
		count = math.max(1, math.min(50, math.floor(count)))

		if target ~= name then
			if not core.check_player_privs(name, { lep_view_rewards = true }) then
				return false, S("You may only view your own rewards.")
			end
			if not core.player_exists(target) then
				return false, S("There is no player @1.", target)
			end
		end

		local entries = lep_rewards.get_log(target, count)
		if #entries == 0 then
			return true, S("@1 has not received any rewards yet.", target)
		end
		local lines = { S("Last rewards of @1 (times in UTC):", target) }
		for _, entry in ipairs(entries) do
			local what = REASONS[entry.reason] or entry.reason
			if entry.module ~= "" then
				what = what .. ", " .. entry.module .. " " .. entry.level
				if entry.task ~= "" then
					what = what .. " " .. entry.task
				end
			end
			lines[#lines + 1] = entry.time .. "  " .. entry.items .. "  (" .. what .. ")"
		end
		return true, table.concat(lines, "\n")
	end,
})
