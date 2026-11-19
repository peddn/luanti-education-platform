-- Removing an account between world and backend. The backend orders it
-- when the school administration or a teacher asks for it in the
-- browser; the world deletes and reports that it did. Only then the
-- backend deletes its copies. See the concept, section 12.
--
-- The world also tells the backend which accounts were ever used: a
-- teacher may take back an account nobody has logged in with.

local load = lep_core.loader("lep_bridge")
local orders = load("src/orders")
local reports = load("src/reports")

if not core.global_exists("lep_accounts") or not lep_accounts.remove then
	return
end

local USED_SYNCED_KEY = "used_synced"
local mod_storage = core.get_mod_storage()

lep_bridge.register_slow_job(reports.JOB_REMOVE_ACCOUNT, function(payload, finish)
	local order = orders.parse_remove_account(payload)
	if not order then
		finish(false, "the order cannot be read")
		return
	end
	lep_accounts.remove(order.account,
		{ only_unused = order.only_unused, staff = order.staff, by = order.by },
		function(ok, why)
			if ok and order.staff and core.global_exists("lep_desk") then
				lep_desk.record(order.by, "web:remove_teacher", order.account)
			end
			-- A fixed word the backend passes on, see
			-- lep_accounts.REMOVAL_REFUSALS.
			finish(ok, ok and "removed" or why)
		end)
end)

-- What still waits to be sent about an account goes with it.
lep_core.register_on_forget_account(function(account)
	local dropped = lep_bridge._drop_events(function(event)
		return reports.concerns(event, account)
	end)
	if dropped > 0 then
		core.log("action", "[lep_bridge] dropped " .. dropped
			.. " waiting event(s) of an account that is removed")
	end
end)

-- The backend hears of every removal, also of one that was done in the
-- world itself, and deletes its copies then.
lep_accounts.register_on_removed(function(account, by)
	lep_bridge.send(reports.EVENT_ACCOUNT_REMOVED, reports.account_removed(account, by))
end)

-- Every login says that the account is in use. Saying it again changes
-- nothing in the backend.
core.register_on_joinplayer(function(player)
	lep_bridge.send(reports.EVENT_ACCOUNT_USED,
		reports.account_used(player:get_player_name()))
end)

local function send_used()
	for name in core.get_auth_handler().iterate() do
		if lep_accounts.was_used(name) then
			lep_bridge.send(reports.EVENT_ACCOUNT_USED, reports.account_used(name))
		end
	end
end

-- When the backend asks for everything: all accounts that were used.
lep_bridge._add_state(send_used)

-- A world that was connected before it reported this says it once.
core.register_on_mods_loaded(function()
	if lep_bridge.is_active() and mod_storage:get_int(USED_SYNCED_KEY) ~= 1 then
		core.after(0, function()
			send_used()
			mod_storage:set_int(USED_SYNCED_KEY, 1)
		end)
	end
end)
