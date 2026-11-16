-- Who is watching whom, and where the watcher came from. Pure Lua, no
-- engine calls.
--
-- A teacher can jump to a student and watch them unseen. The list keeps
-- for every watching teacher the student and the origin: place and
-- position before the first jump. Jumping on to another student keeps
-- that origin, so "back" always leads to where the teacher really was.

local watch = {}

local function is_pos(pos)
	return type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
		and type(pos.z) == "number"
end

local function is_origin(origin)
	return type(origin) == "table" and type(origin.place) == "string" and origin.place ~= ""
		and is_pos(origin.pos)
end

local function copy_origin(origin)
	return { place = origin.place,
		pos = { x = origin.pos.x, y = origin.pos.y, z = origin.pos.z } }
end

local List = {}
List.__index = List

--- Creates a list, empty or from the table that List:data returned.
-- Entries that cannot be read are dropped.
function watch.new(data)
	local list = setmetatable({ _entries = {} }, List)
	if type(data) == "table" then
		for name, entry in pairs(data) do
			if type(name) == "string" and type(entry) == "table" and is_origin(entry.origin)
					and type(entry.target) == "string" then
				list._entries[name] = { origin = copy_origin(entry.origin), target = entry.target }
			end
		end
	end
	return list
end

--- Returns a plain table with everything, for saving.
function List:data()
	local data = {}
	for name, entry in pairs(self._entries) do
		data[name] = { origin = copy_origin(entry.origin), target = entry.target }
	end
	return data
end

--- Notes that a teacher jumps to a student.
-- @param origin Table with place and pos: where the teacher is now. It is
--   only kept if the teacher is not watching yet.
-- @return true if this is the first jump, false if the teacher was
--   watching somebody already
function List:start(watcher, origin, target)
	assert(type(target) == "string" and target ~= "", "target must be a name")
	local entry = self._entries[watcher]
	if entry then
		entry.target = target
		return false
	end
	assert(is_origin(origin), "origin must have a place and a position")
	self._entries[watcher] = { origin = copy_origin(origin), target = target }
	return true
end

--- Returns true if a player is watching somebody.
function List:is_watching(watcher)
	return self._entries[watcher] ~= nil
end

--- Returns the name of the student a player is watching, or nil.
function List:get_target(watcher)
	local entry = self._entries[watcher]
	return entry and entry.target
end

--- Ends the watching of a player. Returns the origin, or nil if the
-- player was not watching.
function List:stop(watcher)
	local entry = self._entries[watcher]
	if not entry then
		return nil
	end
	self._entries[watcher] = nil
	return entry.origin
end

return watch
