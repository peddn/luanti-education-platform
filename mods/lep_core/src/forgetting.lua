-- Who has to be asked when an account is removed. Pure Lua, no engine
-- calls.
--
-- Every mod deletes its own data about an account. It registers a
-- function for that and never has to know who else keeps something.

local forgetting = {}

--- Creates an empty list of the functions to call.
-- @param on_error Optional function(account, err) called when one of
--   them raises an error.
function forgetting.new(on_error)
	local listeners = {}
	local list = {}

	--- Adds a function(account).
	function list.register(_, listener)
		assert(type(listener) == "function", "listener must be a function")
		listeners[#listeners + 1] = listener
	end

	--- Calls every function with the account name. One that fails does
	-- not stop the others.
	-- @return number of functions that failed
	function list.run(_, account)
		local failed = 0
		for index = 1, #listeners do
			local ok, err = pcall(listeners[index], account)
			if not ok then
				failed = failed + 1
				if on_error then
					on_error(account, err)
				end
			end
		end
		return failed
	end

	return list
end

return forgetting
