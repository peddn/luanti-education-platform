-- Creates the accounts of students the backend orders. The start
-- passwords arrive in the job, the world stores only their hash, and
-- nothing here writes them into a log.

local load = lep_core.loader("lep_bridge")
local accounts = load("src/accounts")
local reports = load("src/reports")

-- What the pure core needs to know about this world.
local world = {
	find = function(name)
		local wanted = name:lower()
		for known in core.get_auth_handler().iterate() do
			if known:lower() == wanted then
				return known
			end
		end
		return nil
	end,
	has_password = function(name, password)
		local entry = core.get_auth_handler().get_auth(name)
		return entry ~= nil and core.check_password_entry(name, entry.password, password)
	end,
}

lep_bridge.register_job(reports.JOB_CREATE_ACCOUNTS, function(payload)
	local list = accounts.parse(payload)
	if not list then
		return false, "the order cannot be read"
	end
	local to_create, created, refused = accounts.plan(list, world)
	local handler = core.get_auth_handler()
	for _, entry in ipairs(to_create) do
		-- The engine gives a new account the default privileges.
		handler.create_auth(entry.name, core.get_password_hash(entry.name, entry.password))
		if handler.get_auth(entry.name) then
			created[#created + 1] = entry.name
			core.log("action", "[lep_bridge] account " .. entry.name .. " created")
		else
			refused[#refused + 1] = entry.name
		end
	end
	if #created > 0 or #refused > 0 then
		lep_bridge.send(reports.EVENT_ACCOUNTS_CREATED,
			reports.accounts_created(created, refused))
	end
	return true, #created .. " created, " .. #refused .. " refused"
end)
