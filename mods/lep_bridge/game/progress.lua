-- Passes orders about the progress of students from the backend to
-- lep_progress: a level set by hand, and the lock for moving up. A
-- teacher orders them in the browser. The world makes the change, writes
-- it into the protocol of the desk and reports the new state, as after
-- every change.

local load = lep_core.loader("lep_bridge")
local orders = load("src/orders")
local reports = load("src/reports")

if not core.global_exists("lep_progress") then
	return
end

-- Notes who changed what, as for an action at the desk.
local function record(kind, order)
	local action = orders.describe(kind, order)
	if core.global_exists("lep_desk") then
		lep_desk.record(order.by, action, order.account)
	else
		core.log("action", "[lep_bridge] " .. order.by .. " used " .. action
			.. " on " .. order.account)
	end
end

-- Checks what both orders share. Returns a fixed word the backend
-- passes on, or nil if all is well.
local function refusal(order)
	if not core.get_auth_handler().get_auth(order.account) then
		return "unknown"
	end
	if not lep_progress.get_module(order.module) then
		return "module"
	end
	return nil
end

lep_bridge.register_job(reports.JOB_SET_LEVEL, function(payload)
	local order = orders.parse_level(payload)
	if not order then
		return false, "the order cannot be read"
	end
	local why = refusal(order)
	if why then
		return false, why
	end
	-- The module decides whether it has this level.
	if not lep_progress.set_level(order.account, order.module, order.level) then
		return false, "level"
	end
	record(reports.JOB_SET_LEVEL, order)
	return true, "set"
end)

lep_bridge.register_job(reports.JOB_SET_LOCKED, function(payload)
	local order = orders.parse_locked(payload)
	if not order then
		return false, "the order cannot be read"
	end
	local why = refusal(order)
	if why then
		return false, why
	end
	lep_progress.set_locked(order.account, order.module, order.locked)
	record(reports.JOB_SET_LOCKED, order)
	return true, "set"
end)
