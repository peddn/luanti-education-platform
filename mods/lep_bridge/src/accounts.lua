-- Reading what the backend orders about accounts. Pure Lua, no engine
-- calls. The rules for accounts themselves are in lep_accounts.

local accounts = {}

-- Names arrive from outside and end up in a protocol and in the log.
local function is_name(value)
	return type(value) == "string" and value:match("^[%w_-]+$") ~= nil and #value <= 60
end

--- Reads the payload of the job "create_accounts".
-- @return List of tables with name and password, or nil if the payload
--   cannot be read. Entries that are no table are left out. The second
--   value is nil for students; for teachers it is the account name of
--   the member of the school administration who ordered it.
function accounts.parse(payload)
	if type(payload) ~= "table" or type(payload.accounts) ~= "table" then
		return nil
	end
	local by
	if payload.teacher ~= nil and payload.teacher ~= false then
		-- Accounts with privileges are only created for somebody who
		-- can be named.
		if payload.teacher ~= true or not is_name(payload.by) then
			return nil
		end
		by = payload.by
	end
	local list = {}
	for _, entry in ipairs(payload.accounts) do
		if type(entry) == "table" then
			list[#list + 1] = { name = entry.name, password = entry.password }
		end
	end
	return list, by
end

--- Reads the payload of the job "set_password".
-- @return name and password, or nil if the payload cannot be read. The
--   third value is nil for students; for a teacher it is the account
--   name of the member of the school administration who ordered it.
function accounts.parse_password(payload)
	if type(payload) ~= "table" or type(payload.name) ~= "string" or payload.name == ""
			or type(payload.password) ~= "string" or payload.password == "" then
		return nil
	end
	local by
	if payload.staff ~= nil and payload.staff ~= false then
		if payload.staff ~= true or not is_name(payload.by) then
			return nil
		end
		by = payload.by
	end
	return payload.name, payload.password, by
end

--- Runs jobs one after the other. A job is a function(done) that calls
-- done() when it is finished, at once or later.
-- @param defer Function(next) that calls next() after a pause, so that
--   long work does not happen in one go.
-- @param callback Called without arguments after the last job.
function accounts.run_in_order(jobs, defer, callback)
	local function step(index)
		local job = jobs[index]
		if not job then
			callback()
			return
		end
		local finished = false
		job(function()
			-- A job that reports twice must not start the next one twice.
			if finished then
				return
			end
			finished = true
			defer(function()
				step(index + 1)
			end)
		end)
	end
	step(1)
end

return accounts
