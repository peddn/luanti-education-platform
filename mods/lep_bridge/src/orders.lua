-- Reading what the backend orders about the progress of students. Pure
-- Lua, no engine calls. The rules of progress are in lep_progress.

local orders = {}

-- Names arrive from outside and end up in a protocol and in the log.
local function is_name(value)
	return type(value) == "string" and value:match("^[%w_-]+$") ~= nil and #value <= 60
end

local function is_module(value)
	return type(value) == "string" and value:match("^[%w_]+:[%w_]+$") ~= nil
end

-- Reads what both orders share.
local function target(payload)
	if type(payload) ~= "table" or not is_name(payload.account)
			or not is_name(payload.by) or not is_module(payload.module) then
		return nil
	end
	return { account = payload.account, module = payload.module, by = payload.by }
end

--- Reads the payload of the job "set_level".
-- @return Table with account, module, level and by, or nil if the
--   payload cannot be read.
function orders.parse_level(payload)
	local order = target(payload)
	local level = order and payload.level
	if type(level) ~= "number" or level ~= math.floor(level) or level < 1 then
		return nil
	end
	order.level = level
	return order
end

--- Reads the payload of the job "set_locked".
-- @return Table with account, module, locked and by, or nil if the
--   payload cannot be read.
function orders.parse_locked(payload)
	local order = target(payload)
	if not order or type(payload.locked) ~= "boolean" then
		return nil
	end
	order.locked = payload.locked
	return order
end

--- Returns the line for the protocol of the desk.
function orders.describe(kind, order)
	if kind == "set_level" then
		return "web:set_level " .. order.module .. " " .. order.level
	end
	return "web:set_locked " .. order.module .. " " .. (order.locked and "on" or "off")
end

return orders
