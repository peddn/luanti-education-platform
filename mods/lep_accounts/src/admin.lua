-- The account of the admin from the settings. A new world creates it
-- by itself with a start password, so nobody can take it over by being
-- the first to walk in. Pure logic: what to do, and how a start password
-- is made from random bytes.

local admin = {}

-- Letters and digits that are not mistaken for each other when read
-- from a screen and typed: no l, o, 0 or 1. Exactly 32 of them, so one
-- byte picks one without preferring any.
admin.ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789"

-- Groups of four, like 'k7mw-3xqa-…'. Twenty characters hold 100 bits.
admin.GROUPS = 5
admin.GROUP_LENGTH = 4

--- Returns how many random bytes a start password needs.
function admin.bytes_needed()
	return admin.GROUPS * admin.GROUP_LENGTH
end

--- Makes a start password from random bytes.
-- @param bytes String of at least bytes_needed() bytes from a secure
--   source.
-- @return The password, or nil if there are too few bytes.
function admin.password_from(bytes)
	if type(bytes) ~= "string" or #bytes < admin.bytes_needed() then
		return nil
	end
	local groups = {}
	for group = 1, admin.GROUPS do
		local characters = {}
		for place = 1, admin.GROUP_LENGTH do
			local byte = bytes:byte((group - 1) * admin.GROUP_LENGTH + place)
			local index = byte % #admin.ALPHABET + 1
			characters[place] = admin.ALPHABET:sub(index, index)
		end
		groups[group] = table.concat(characters)
	end
	return table.concat(groups, "-")
end

--- Returns true if a text can be the name of the admin.
function admin.is_set(name)
	return type(name) == "string" and name ~= ""
end

-- What the world does about the account of the admin.
admin.CREATE = "create"           -- make the account with a start password
admin.FORGET = "forget"           -- the start password is no longer in use
admin.NOTHING = "nothing"

--- Decides what to do.
-- @param name Name of the admin from the settings, or nil.
-- @param exists True if there is an account with this name.
-- @param noted The start password the world noted down, or nil if it
--   noted none.
-- @param still_valid True if the account still has the noted password.
function admin.decide(name, exists, noted, still_valid)
	if not admin.is_set(name) then
		return admin.NOTHING
	end
	if not exists then
		return admin.CREATE
	end
	if noted ~= nil and not still_valid then
		return admin.FORGET
	end
	return admin.NOTHING
end

return admin
