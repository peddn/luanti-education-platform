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
reports.JOB_SYNC_STATE = "sync_state"

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

return reports
