-- Minimal observer pattern: mods register callbacks for named events,
-- other code emits them. Pure Lua, no engine calls.

local events = {}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

--- Creates a new, empty dispatcher.
-- @param on_error Optional function(event_name, err) called when a callback
--        raises an error. Defaults to ignoring the error.
function events.new(on_error)
	assert(on_error == nil or type(on_error) == "function",
		"events.new: on_error must be a function or nil")
	return setmetatable({
		_callbacks = {},
		_on_error = on_error,
	}, Dispatcher)
end

--- Registers a callback for an event.
-- Callbacks run in the order they were registered.
function Dispatcher:register(event_name, callback)
	assert(type(event_name) == "string" and event_name ~= "",
		"register: event_name must be a non-empty string")
	assert(type(callback) == "function",
		"register: callback must be a function")

	local list = self._callbacks[event_name]
	if not list then
		list = {}
		self._callbacks[event_name] = list
	end
	list[#list + 1] = callback
end

--- Calls all callbacks of an event with the given arguments.
-- A failing callback does not stop the others.
-- @return Number of callbacks that ran without error, number that failed.
function Dispatcher:emit(event_name, ...)
	assert(type(event_name) == "string" and event_name ~= "",
		"emit: event_name must be a non-empty string")

	local list = self._callbacks[event_name]
	if not list then
		return 0, 0
	end

	local succeeded, failed = 0, 0
	-- Iterate over a fixed length so callbacks registered during emit
	-- only run on the next emit.
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if ok then
			succeeded = succeeded + 1
		else
			failed = failed + 1
			if self._on_error then
				self._on_error(event_name, err)
			end
		end
	end
	return succeeded, failed
end

--- Returns how many callbacks are registered for an event.
function Dispatcher:count(event_name)
	local list = self._callbacks[event_name]
	return list and #list or 0
end

--- Returns a function that registers a callback for one fixed event.
-- Used to build public "register_on_<event>" functions.
function Dispatcher:registrar(event_name)
	assert(type(event_name) == "string" and event_name ~= "",
		"registrar: event_name must be a non-empty string")
	return function(callback)
		self:register(event_name, callback)
	end
end

return events
