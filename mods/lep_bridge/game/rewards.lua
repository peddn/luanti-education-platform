-- The reward table between world and backend. The world keeps it; a
-- teacher changes it in the browser, which arrives here as a job. The
-- world reports the table and the items a teacher may choose from.

local load = lep_core.loader("lep_bridge")
local orders = load("src/orders")
local reports = load("src/reports")

if not core.global_exists("lep_rewards") or not lep_rewards.get_table then
	return
end

-- Names of items leave the world in its language, like all texts.
local function send_rewards()
	local choices = lep_rewards.get_choices()
	for _, choice in ipairs(choices) do
		choice.title = core.get_translated_string("de", choice.title)
	end
	lep_bridge.send(reports.EVENT_REWARDS, reports.rewards(lep_rewards.get_table(), choices))
end

lep_rewards.register_on_table_changed(send_rewards)
lep_bridge._add_state(send_rewards)

-- The list of items may have changed with the settings.
core.register_on_mods_loaded(function()
	if lep_bridge.is_active() then
		core.after(0, send_rewards)
	end
end)

lep_bridge.register_job(reports.JOB_SET_REWARDS, function(payload)
	local order = orders.parse_rewards(payload, reports.reward_table)
	if not order then
		return false, "the order cannot be read"
	end
	local action = "web:reset_rewards"
	if order.reset then
		lep_rewards.reset_table()
	else
		local ok, why = lep_rewards.set_table(order.table)
		if not ok then
			-- A fixed word: the row that is wrong, or "daily_limit".
			return false, why
		end
		action = "web:set_rewards"
	end
	if core.global_exists("lep_desk") then
		lep_desk.record(order.by, action)
	end
	return true, "set"
end)
