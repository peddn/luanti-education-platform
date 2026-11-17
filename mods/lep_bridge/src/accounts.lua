-- Accounts the backend asks this world to create. Pure Lua, no engine
-- calls.

local accounts = {}

-- Longest name the engine takes (tried with Luanti 5.18). The backend
-- stays one below.
accounts.MAX_NAME = 20

--- Returns true if a text is a name the engine takes for a player.
function accounts.is_name(name)
	return type(name) == "string" and #name >= 1 and #name <= accounts.MAX_NAME
		and name:find("^[%w_%-]+$") ~= nil
end

--- Reads the payload of the job "create_accounts".
-- @return List of tables with name and password, or nil if the payload
--   cannot be read. Entries that are no pair of two texts are left out
--   here and refused later by their name, if they have one.
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

--- Decides what to do with each ordered account.
-- @param list From accounts.parse.
-- @param world Table of functions about this world:
--   find(name)             returns the name of an existing account that
--                          equals `name` in any letter case, or nil
--   has_password(name, pw) returns true if the account has this password
-- @return to_create (list of name and password), created (names that
--   exist already with exactly this password, from an earlier run of the
--   same job), refused (names)
function accounts.plan(list, world)
	local to_create, created, refused = {}, {}, {}
	local seen = {}
	for _, entry in ipairs(list) do
		local name, password = entry.name, entry.password
		local key = type(name) == "string" and name:lower() or nil
		if not accounts.is_name(name) or type(password) ~= "string" or password == ""
				or seen[key] then
			if type(name) == "string" and name ~= "" then
				refused[#refused + 1] = name
			end
		else
			seen[key] = true
			local existing = world.find(name)
			if not existing then
				to_create[#to_create + 1] = { name = name, password = password }
			elseif existing == name and world.has_password(name, password) then
				-- The job arrived before and was done. An account of
				-- somebody else would not have this password.
				created[#created + 1] = name
			else
				-- Taken. The account of somebody else is never touched.
				refused[#refused + 1] = name
			end
		end
	end
	return to_create, created, refused
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
