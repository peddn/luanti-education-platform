-- Chat commands of lep_rewards.

local S = core.get_translator("lep_rewards")

core.register_privilege("lep_view_rewards", {
	description = "Can view the reward protocol of other players",
	give_to_singleplayer = false,
	give_to_admin = true,
})

core.register_chatcommand("lep_rewards", {
	description = S("Show what the rewards contain and how many daily tasks are left today"),
	func = function(name)
		local remaining, limit = lep_rewards.get_remaining(name)
		local function items(occasion)
			return lep_rewards.describe_items(lep_rewards.get_reward(occasion))
		end
		local lines = {
			S("For a solved task: @1", items(lep_rewards.TASK)),
			S("For a completed level: @1", items(lep_rewards.LEVEL)),
			S("For a completed stage: @1", items(lep_rewards.STAGE)),
			S("For a completed module: @1", items(lep_rewards.MODULE)),
			S("Harder tasks and modules earn twice or three times as much."),
			S("Daily tasks left today: @1 of @2", remaining, limit),
		}
		return true, table.concat(lines, "\n")
	end,
})

local REASONS = {
	task = S("level task"),
	daily = S("daily task"),
	level = S("level completed"),
	stage = S("stage completed"),
	module = S("module completed"),
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
