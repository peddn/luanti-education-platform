-- Where the list of chests is kept between server starts.

local storage = {}

local mod_storage = core.get_mod_storage()

--- Returns the stored list, or nil if there is none.
function storage.load()
	return core.deserialize(mod_storage:get_string("chests"))
end

--- Stores the list.
function storage.save(data)
	mod_storage:set_string("chests", core.serialize(data))
end

return storage
