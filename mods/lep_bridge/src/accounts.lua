-- Reading what the backend orders about accounts. Pure Lua, no engine
-- calls. The rules for accounts themselves are in lep_accounts.

local accounts = {}

--- Reads the payload of the job "create_accounts".
-- @return List of tables with name and password, or nil if the payload
--   cannot be read. Entries that are no table are left out.
function accounts.parse(payload)
	if type(payload) ~= "table" or type(payload.accounts) ~= "table" then
		return nil
	end
	local list = {}
	for _, entry in ipairs(payload.accounts) do
		if type(entry) == "table" then
			list[#list + 1] = { name = entry.name, password = entry.password }
		end
	end
	return list
end

--- Reads the payload of the job "set_password".
-- @return name and password, or nil if the payload cannot be read
function accounts.parse_password(payload)
	if type(payload) ~= "table" or type(payload.name) ~= "string" or payload.name == ""
			or type(payload.password) ~= "string" or payload.password == "" then
		return nil
	end
	return payload.name, payload.password
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
