-- Where the display names are kept. Only this file knows the storage.

local storage = {}

local mod_storage = core.get_mod_storage()
local PREFIX = "name:"

--- Returns the stored state of an account, or nil.
function storage.load(account)
	local text = mod_storage:get_string(PREFIX .. account)
	if text == "" then
		return nil
	end
	return core.parse_json(text)
end

--- Stores the state of an account.
function storage.save(account, state)
	mod_storage:set_string(PREFIX .. account, core.write_json(state))
end

--- Deletes the stored state of an account.
function storage.remove(account)
	mod_storage:set_string(PREFIX .. account, "")
end

--- Returns the names of all accounts with a stored state.
function storage.accounts()
	local list = {}
	for _, key in ipairs(mod_storage:get_keys()) do
		if key:sub(1, #PREFIX) == PREFIX then
			list[#list + 1] = key:sub(#PREFIX + 1)
		end
	end
	return list
end

return storage
