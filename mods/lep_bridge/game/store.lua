-- Where the queue of events is kept between server starts: the storage
-- of this mod, one entry per event.

local mod_storage = core.get_mod_storage()

local store = {}

--- Returns the stored value: a table for an event, a text for a counter.
function store.get(key)
	local text = mod_storage:get_string(key)
	if text == "" then
		return nil
	end
	if key:sub(1, 6) == "event:" then
		return core.parse_json(text, nil, true)
	end
	return text
end

--- Stores a value. nil removes the entry.
function store.set(key, value)
	if value == nil then
		mod_storage:set_string(key, "")
	elseif type(value) == "table" then
		mod_storage:set_string(key, core.write_json(value))
	else
		mod_storage:set_string(key, tostring(value))
	end
end

return store
