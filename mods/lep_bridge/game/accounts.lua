-- Creates the accounts of students the backend orders. The start
-- passwords arrive in the job, the world stores only their hash, and
-- nothing here writes them into a log.
--
-- For every new account the rooms are built ahead: the room in the lobby
-- and the rooms of the learning modules. On the first day a whole class
-- logs in at the same moment, and nothing has to be built then.

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

-- Seconds between two rooms in the lobby, so the server stays playable.
local BUILD_PAUSE = 0.3

-- Builds everything the owners of new accounts need, one room after the
-- other. Rooms that exist are left alone, so doing this twice is fine.
local function build_rooms(names)
	if #names == 0 then
		return
	end
	local started = os.time()
	local jobs = {}
	if core.global_exists("lep_lobby") then
		for _, name in ipairs(names) do
			jobs[#jobs + 1] = function(done)
				lep_lobby.ensure_room(name, done)
			end
		end
	end
	if core.global_exists("lep_rooms") then
		jobs[#jobs + 1] = function(done)
			lep_rooms.prebuild_all(names, function(_, failed)
				if failed > 0 then
					core.log("warning", "[lep_bridge] " .. failed
						.. " room(s) could not be built ahead; they are built when entered")
				end
				done()
			end)
		end
	end
	accounts.run_in_order(jobs, function(next_step)
		core.after(BUILD_PAUSE, next_step)
	end, function()
		core.log("action", "[lep_bridge] rooms for " .. #names .. " new account(s) built in "
			.. (os.time() - started) .. " s")
	end)
end

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
	-- The job is done once the accounts exist. The rooms follow in the
	-- background; a room that is missing is built when it is entered.
	build_rooms(created)
	if #created > 0 or #refused > 0 then
		lep_bridge.send(reports.EVENT_ACCOUNTS_CREATED,
			reports.accounts_created(created, refused))
	end
	return true, #created .. " created, " .. #refused .. " refused"
end)
