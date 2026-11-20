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

--- Reads the payload of the job "set_start_level".
-- @return Table with module, level and by, or nil if the payload cannot
--   be read.
function orders.parse_start_level(payload)
	if type(payload) ~= "table" or not is_module(payload.module) or not is_name(payload.by) then
		return nil
	end
	local level = payload.level
	if type(level) ~= "number" or level ~= math.floor(level) or level < 1 then
		return nil
	end
	return { module = payload.module, level = level, by = payload.by }
end

-- Reads what the two orders about display names share.
local function name_target(payload)
	if type(payload) ~= "table" or not is_name(payload.account) or not is_name(payload.by) then
		return nil
	end
	return { account = payload.account, by = payload.by }
end

--- Reads the payload of the job "remove_display_name".
-- @return Table with account and by, or nil if the payload cannot be
--   read.
function orders.parse_remove_name(payload)
	return name_target(payload)
end

--- Reads the payload of the job "set_display_locked".
-- @return Table with account, locked and by, or nil if the payload
--   cannot be read.
function orders.parse_name_lock(payload)
	local order = name_target(payload)
	if not order or type(payload.locked) ~= "boolean" then
		return nil
	end
	order.locked = payload.locked
	return order
end

--- Reads the payload of the job "clear_protocols".
-- @return Table with by, or nil if the payload cannot be read.
function orders.parse_clear(payload)
	if type(payload) ~= "table" or not is_name(payload.by) then
		return nil
	end
	return { by = payload.by }
end

--- Reads the payload of the job "remove_account".
-- @return Table with account, by and only_unused, or nil if the payload
--   cannot be read.
function orders.parse_remove_account(payload)
	local order = name_target(payload)
	if not order or type(payload.only_unused) ~= "boolean" then
		return nil
	end
	order.only_unused = payload.only_unused
	-- Meant for a teacher: only the school administration orders that.
	if payload.staff ~= nil and type(payload.staff) ~= "boolean" then
		return nil
	end
	order.staff = payload.staff == true
	return order
end

--- Reads the payload of the job "set_rewards".
-- @param read_table Function that reads a reward table, see
--   reports.reward_table.
-- @return Table with by and either table or reset = true, or nil if the
--   payload cannot be read.
function orders.parse_rewards(payload, read_table)
	if type(payload) ~= "table" or not is_name(payload.by) then
		return nil
	end
	if payload.table == nil then
		return { by = payload.by, reset = true }
	end
	local wanted = read_table(payload.table)
	if not wanted then
		return nil
	end
	return { by = payload.by, table = wanted }
end

--- Returns the line for the protocol of the desk.
function orders.describe(kind, order)
	if kind == "set_level" then
		return "web:set_level " .. order.module .. " " .. order.level
	elseif kind == "set_start_level" then
		return "web:set_start_level " .. order.module .. " " .. order.level
	end
	return "web:set_locked " .. order.module .. " " .. (order.locked and "on" or "off")
end

return orders
