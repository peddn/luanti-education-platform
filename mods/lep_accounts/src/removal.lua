-- Rules for removing an account on request, see the concept, section 12.
-- Pure Lua, no engine calls.

local removal = {}

-- Why an account is not removed.
removal.UNKNOWN = "unknown"        -- there is no such account
removal.STAFF = "staff"            -- it holds more than every new player gets
removal.USED = "used"              -- somebody has logged in with it
removal.BUSY = "busy"              -- it is being removed right now
removal.ONLINE = "online"          -- the player could not be disconnected
removal.INCOMPLETE = "incomplete"  -- something could not be deleted

--- Returns true if somebody has ever logged in with an account.
-- @param last_login What the engine keeps: the time of the last login,
--   and no time for an account that was only created.
function removal.was_used(last_login)
	return type(last_login) == "number" and last_login > 0
end

--- Decides whether an account may be removed from outside.
-- @param exists True if there is exactly this account.
-- @param is_ordinary True if it holds nothing but what every new player
--   gets. Nobody removes a teacher or an admin this way.
-- @param used True if somebody has ever logged in with it.
-- @param only_unused True if who asks may only remove accounts nobody
--   ever used: a teacher takes back what they created.
-- @return true, or false and why not: UNKNOWN, STAFF or USED
function removal.may_remove(exists, is_ordinary, used, only_unused)
	if not exists then
		return false, removal.UNKNOWN
	elseif not is_ordinary then
		return false, removal.STAFF
	elseif only_unused and used then
		return false, removal.USED
	end
	return true
end

return removal
