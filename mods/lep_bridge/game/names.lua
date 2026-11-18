-- Display names between world and backend. The world reports the state
-- of an account after every change, and the backend orders what a
-- teacher decided in the browser: taking a name away, and locking or
-- unlocking choosing one. Rules and storage are in lep_accounts.

local load = lep_core.loader("lep_bridge")
local orders = load("src/orders")
local reports = load("src/reports")

if not core.global_exists("lep_accounts") or not lep_accounts.get_display_state then
	return
end

local function send(account)
	lep_bridge.send(reports.EVENT_DISPLAY_NAME,
		reports.display_name(account, lep_accounts.get_display_state(account)))
end

-- Every change is reported as the new state of the account.
lep_accounts.register_on_display_name_changed(send)

-- When the backend asks for everything: all accounts with a name or a
-- lock.
lep_bridge._add_state(function()
	for _, account in ipairs(lep_accounts.get_display_accounts()) do
		send(account)
	end
end)

lep_bridge.register_job(reports.JOB_REMOVE_DISPLAY_NAME, function(payload)
	local order = orders.parse_remove_name(payload)
	if not order then
		return false, "the order cannot be read"
	end
	if not lep_accounts.exists(order.account) then
		return false, "unknown"
	end
	-- An account without a name is fine: the order may arrive twice.
	lep_accounts.remove_display_name(order.account, order.by)
	return true, "removed"
end)

lep_bridge.register_job(reports.JOB_SET_DISPLAY_LOCKED, function(payload)
	local order = orders.parse_name_lock(payload)
	if not order then
		return false, "the order cannot be read"
	end
	if not lep_accounts.exists(order.account) then
		return false, "unknown"
	end
	lep_accounts.set_display_locked(order.account, order.locked, order.by)
	return true, order.locked and "locked" or "unlocked"
end)
