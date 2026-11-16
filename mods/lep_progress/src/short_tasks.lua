-- Short tasks: tasks that fit into a small window with one line of text
-- and one input field. Pure Lua, no engine calls.
--
-- Learning modules that can make up such tasks register a provider. Other
-- mods, for example the task chest, ask for a task without knowing the
-- module it comes from.
--
-- A provider is a function(player_name) that returns nil or a table with
--   text    the question as readable text, for example "7 + 5 = ?"
--   task    id of the task type, as in the module's levels
--   level   level the task belongs to
--   check   function(input) returning true if the typed text is right
-- The solution stays inside `check`. Whoever shows the task never sees it.

local short_tasks = {}

local Registry = {}
Registry.__index = Registry

--- Creates an empty registry of providers.
function short_tasks.new()
	return setmetatable({ _ids = {}, _providers = {} }, Registry)
end

--- Registers the provider of a module. A module has one provider.
function Registry:register(module_id, provider)
	assert(type(module_id) == "string" and module_id ~= "",
		"module id must be a non-empty string")
	assert(type(provider) == "function", "provider must be a function")
	assert(not self._providers[module_id],
		"module '" .. module_id .. "' already has short tasks")
	self._ids[#self._ids + 1] = module_id
	self._providers[module_id] = provider
end

--- Returns the ids of the modules with short tasks, in the order they
-- were registered.
function Registry:ids()
	local copy = {}
	for index, id in ipairs(self._ids) do
		copy[index] = id
	end
	return copy
end

local function is_valid(task)
	return type(task) == "table"
		and type(task.text) == "string" and task.text ~= ""
		and type(task.task) == "string" and task.task ~= ""
		and type(task.level) == "number"
		and type(task.check) == "function"
end

--- Returns a short task for a player from one of the modules, or nil if
-- no module has one. The module is chosen at random; if it has nothing
-- for this player, the others are tried in turn.
-- @param random Function(min, max) returning a whole number in that range.
-- @param on_error Optional function(module_id, err) for providers that
--   fail or return something unusable.
-- @return Table with module, task, level, text and check.
function Registry:pick(player_name, random, on_error)
	local count = #self._ids
	if count == 0 then
		return nil
	end
	local first = random(1, count)
	for step = 0, count - 1 do
		local module_id = self._ids[(first - 1 + step) % count + 1]
		local ok, task = pcall(self._providers[module_id], player_name)
		if ok and is_valid(task) then
			return {
				module = module_id,
				task = task.task,
				level = task.level,
				text = task.text,
				check = task.check,
			}
		elseif on_error and (not ok or task ~= nil) then
			on_error(module_id, ok and "provider returned an unusable task" or task)
		end
	end
	return nil
end

return short_tasks
