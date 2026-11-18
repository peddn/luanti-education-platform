-- What the world reports to the backend about its students, as payloads
-- of events. Pure Lua, no engine calls.
--
-- The shapes are defined in crates/protocol. The tests of this file check
-- what is built here against api/openapi.json. The world writes, the
-- backend mirrors: every payload carries a whole state, never a change.

local reports = {}

reports.EVENT_MODULES = "modules"
reports.EVENT_PROGRESS = "progress"
reports.EVENT_TROPHIES = "trophies"
reports.EVENT_PROTOCOL = "protocol"
reports.EVENT_TEACHERS = "teachers"
reports.EVENT_WEB_ACCESS = "web_access"
reports.EVENT_ACCOUNTS_CREATED = "accounts_created"
reports.EVENT_DISPLAY_NAME = "display_name"
reports.JOB_CREATE_ACCOUNTS = "create_accounts"
reports.JOB_SET_PASSWORD = "set_password"
reports.JOB_SET_LEVEL = "set_level"
reports.JOB_SET_LOCKED = "set_locked"
reports.JOB_REMOVE_DISPLAY_NAME = "remove_display_name"
reports.JOB_SET_DISPLAY_LOCKED = "set_display_locked"
reports.JOB_SYNC_STATE = "sync_state"
reports.JOB_WEB_ACCESS_STATUS = "web_access_status"

-- What a teacher can do with their web access.
local WEB_ACCESS_ACTIONS = { set = true, resend = true, remove = true }

local function whole(number)
	return math.max(0, math.floor(tonumber(number) or 0))
end

--- Builds the payload of the event "modules".
-- @param modules List of { id, title, levels }, where levels is a list of
--   { stage, tasks } and tasks a list of { id, title, required }. Titles
--   are plain text, already in the language of the world.
function reports.modules(modules)
	local list = {}
	for index, module in ipairs(modules) do
		local levels = {}
		for number, level in ipairs(module.levels) do
			local tasks = {}
			for position, task in ipairs(level.tasks) do
				tasks[position] = {
					id = task.id,
					title = tostring(task.title),
					required = whole(task.required),
				}
			end
			levels[number] = { stage = level.stage == true, tasks = tasks }
		end
		list[index] = { id = module.id, title = tostring(module.title), levels = levels }
	end
	return { modules = list }
end

--- Builds the payload of the event "progress".
-- @param info What lep_progress.get_progress returns.
function reports.progress(account, info)
	local tasks = {}
	for index, task in ipairs(info.tasks) do
		tasks[index] = { id = task.id, solved = whole(task.solved),
			required = whole(task.required) }
	end
	return {
		account = account,
		module = info.module_id,
		level = whole(info.level),
		locked = info.locked == true,
		percent = math.min(100, whole(info.percent)),
		completed = info.completed == true,
		tasks = tasks,
	}
end

--- Builds the payload of the event "trophies".
-- @param trophies List of { id, title, material }.
function reports.trophies(account, trophies)
	local list = {}
	for index, trophy in ipairs(trophies) do
		list[index] = { id = trophy.id, title = tostring(trophy.title),
			material = tostring(trophy.material) }
	end
	return { account = account, trophies = list }
end

--- Builds the payload of the event "display_name": what an account is
-- shown under. Always the whole state.
-- @param state Table with display, changed_at and locked, as
--   lep_accounts.get_display_state returns it.
function reports.display_name(account, state)
	return {
		account = account,
		name = type(state.display) == "string" and state.display or nil,
		changed_at = type(state.changed_at) == "number" and math.floor(state.changed_at) or nil,
		locked = state.locked == true,
	}
end

--- Builds the payload of the event "protocol" from an entry of a
-- protocol, or returns nil if the entry names no account.
-- @param name Name of the protocol.
-- @param record Table with a value per column, as it was written.
function reports.protocol(name, record)
	local account = record.account
	if type(account) ~= "string" or account == "" then
		return nil
	end
	local fields = {}
	for column, value in pairs(record) do
		if column ~= "account" and type(column) == "string" and value ~= nil then
			local text = tostring(value)
			if text ~= "" then
				fields[column] = text
			end
		end
	end
	return { protocol = name, account = account, fields = fields }
end

--- Builds the payload of the event "teachers": the accounts that hold
-- the privilege for web access in this world.
-- @param school_admins The accounts that hold the privilege of the school
--   administration.
function reports.teachers(accounts, school_admins)
	local function names(list)
		local copy = {}
		for index, account in ipairs(list or {}) do
			copy[index] = tostring(account)
		end
		return copy
	end
	return { accounts = names(accounts), school_admins = names(school_admins) }
end

--- Builds the payload of the event "accounts_created": the names of the
-- accounts that exist now, and of those that were refused.
function reports.accounts_created(created, refused)
	local function names(list)
		local copy = {}
		for index, name in ipairs(list or {}) do
			copy[index] = tostring(name)
		end
		return copy
	end
	return { created = names(created), refused = names(refused) }
end

--- Builds the payload of the event "web_access": what a teacher did with
-- their web access at the desk.
-- @param action "set", "resend" or "remove"
-- @param email The address, for "set" only.
function reports.web_access(account, action, email)
	assert(type(account) == "string" and account ~= "", "web access needs an account")
	assert(WEB_ACCESS_ACTIONS[action], "unknown web access action '" .. tostring(action) .. "'")
	local payload = { account = account, action = action }
	if action == "set" then
		assert(type(email) == "string" and email ~= "", "setting web access needs an address")
		payload.email = email
	end
	return payload
end

--- Reads the payload of the job "web_access_status".
-- @return account, address, pending (shortened addresses or nil), or nil
--   if the payload cannot be read
function reports.parse_web_access_status(payload)
	if type(payload) ~= "table" or type(payload.account) ~= "string"
			or payload.account == "" then
		return nil
	end
	local function text(value)
		return type(value) == "string" and value ~= "" and value or nil
	end
	return payload.account, text(payload.address), text(payload.pending)
end

return reports
