-- The queue of events that wait to be sent to the backend. Pure Lua, no
-- engine calls.
--
-- Events are stored before they are sent and removed only when the
-- backend has answered for them, so nothing is lost when the connection
-- or the server goes down. The queue keeps every event under its own key
-- in a store that is passed in:
--   store.get(key)         returns the stored value or nil
--   store.set(key, value)  stores a value, nil removes it
-- Adding and removing an event touches a few keys, however long the queue
-- is.

local queue = {}

-- Most events the queue keeps. Beyond that the oldest are dropped.
queue.DEFAULT_LIMIT = 50000

local Queue = {}
Queue.__index = Queue

local function event_key(seq)
	return "event:" .. seq
end

--- Opens the queue in a store. What was stored before is still there.
-- @param options Optional table with `limit`.
function queue.new(store, options)
	assert(type(store) == "table" and type(store.get) == "function"
		and type(store.set) == "function", "store needs get and set")
	local limit = options and options.limit or queue.DEFAULT_LIMIT
	assert(type(limit) == "number" and limit >= 1, "limit must be a number from 1")
	local self = setmetatable({ _store = store, _limit = limit }, Queue)
	-- Sequence numbers: `head` is the oldest event, `tail` the next free one.
	self._head = tonumber(store.get("head")) or 1
	self._tail = tonumber(store.get("tail")) or self._head
	if self._tail < self._head then
		self._tail = self._head
	end
	return self
end

--- Returns how many events wait.
function Queue:size()
	return self._tail - self._head
end

local function drop_head(self)
	self._store.set(event_key(self._head), nil)
	self._head = self._head + 1
	self._store.set("head", tostring(self._head))
end

--- Adds an event at the end.
-- @param event Table with id, kind, time and payload.
-- @return how many old events were dropped because the queue was full
function Queue:push(event)
	assert(type(event) == "table" and type(event.id) == "string" and event.id ~= "",
		"an event needs an id")
	self._store.set(event_key(self._tail), event)
	self._tail = self._tail + 1
	self._store.set("tail", tostring(self._tail))
	local dropped = 0
	while self:size() > self._limit do
		drop_head(self)
		dropped = dropped + 1
	end
	return dropped
end

--- Returns up to `count` events from the front, oldest first, without
-- removing them. Entries that can no longer be read are skipped and
-- removed.
function Queue:peek(count)
	local events = {}
	local seq = self._head
	while #events < count and seq < self._tail do
		local event = self._store.get(event_key(seq))
		if type(event) == "table" and type(event.id) == "string" then
			events[#events + 1] = event
		elseif seq == self._head then
			-- Broken entry at the front: nothing can be done with it.
			drop_head(self)
		end
		seq = seq + 1
	end
	return events
end

--- Removes the events the backend has answered for.
-- @param ids List of ids of events from the front of the queue.
-- @return how many events were removed
function Queue:remove(ids)
	local answered = {}
	for _, id in ipairs(ids) do
		answered[id] = true
	end
	local removed = 0
	while self._head < self._tail do
		local event = self._store.get(event_key(self._head))
		local readable = type(event) == "table" and type(event.id) == "string"
		if readable and not answered[event.id] then
			break
		end
		drop_head(self)
		if readable then
			removed = removed + 1
		end
	end
	return removed
end

--- Removes the waiting events a function picks, wherever they stand.
-- @param matches Function(event) returning true for an event to drop.
-- @return how many events were removed
function Queue:drop_where(matches)
	local removed = 0
	for seq = self._head, self._tail - 1 do
		local event = self._store.get(event_key(seq))
		if type(event) == "table" and matches(event) then
			-- The gap is skipped when the queue is read.
			self._store.set(event_key(seq), nil)
			removed = removed + 1
		end
	end
	return removed
end

return queue
