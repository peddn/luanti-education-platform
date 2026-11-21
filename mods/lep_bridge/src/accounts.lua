-- Reading what the backend orders about accounts. Pure Lua, no engine
-- calls. The rules for accounts themselves are in lep_accounts.

local accounts = {}

-- Names arrive from outside and end up in a protocol and in the log.
local function is_name(value)
	return type(value) == "string" and value:match("^[%w_-]+$") ~= nil and #value <= 60
end

-- Reads the version of a password: a whole number from 0 on, or nil.
local function version_of(value)
	if type(value) == "number" and value >= 0 and value == math.floor(value)
			and value < 2 ^ 31 then
		return value
	end
	return nil
end

--- Reads the payload of the job "create_accounts".
-- @return List of tables with name and password, or nil if the payload
--   cannot be read. A teacher may come with `entry` instead of a
--   password. Entries that are no table are left out. The second
--   value is nil for students; for teachers it is the account name of
--   the member of the school administration who ordered it. The third
--   is the version of the passwords, for teachers, or nil.
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
			-- What is stored of a password is only taken for teachers.
			if entry.entry ~= nil and not by then
				return nil
			end
			list[#list + 1] = { name = entry.name, password = entry.password,
				entry = entry.entry }
		end
	end
	return list, by, by and version_of(payload.version) or nil
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

--- Reads the payload of the job "set_password_entry".
-- @return name, entry and version, or nil if the payload cannot be read.
--   The fourth value is the account name of the member of the school
--   administration who ordered a new start password, or nil if the
--   password comes from another world.
function accounts.parse_entry(payload)
	if type(payload) ~= "table" or not is_name(payload.name)
			or type(payload.entry) ~= "string" or payload.entry == ""
			or not version_of(payload.version)
			or payload.by ~= nil and not is_name(payload.by) then
		return nil
	end
	return payload.name, payload.entry, payload.version, payload.by
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
