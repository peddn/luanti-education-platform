-- Public API of lep_accounts: creating accounts and setting passwords.
-- Both are done on order from outside, so both check everything again
-- here. No password is written into a log.

local load = lep_core.loader("lep_accounts")
local accounts = load("src/accounts")

--- Returns the name of the account that equals a name in any letter
-- case, or nil. The engine does not allow two names that differ only
-- there.
function lep_accounts.find(name)
	if type(name) ~= "string" then
		return nil
	end
	local wanted = name:lower()
	for known in core.get_auth_handler().iterate() do
		if known:lower() == wanted then
			return known
		end
	end
	return nil
end

--- Returns true if there is exactly this account.
function lep_accounts.exists(name)
	return type(name) == "string" and core.get_auth_handler().get_auth(name) ~= nil
end

local function has_password(name, password)
	local entry = core.get_auth_handler().get_auth(name)
	return entry ~= nil and core.check_password_entry(name, entry.password, password)
end

-- The privileges every new player gets. An account that holds nothing
-- else is an ordinary one.
local function ordinary_privileges()
	return accounts.privilege_set(core.settings:get("default_privs"))
end

--- Creates accounts with a start password each.
-- An account that exists is never touched: its name is refused. Only an
-- account that exists with exactly this password counts as created,
-- because then the same order was done before.
-- @param list List of tables with name and password.
-- @return created (list of names), refused (list of names)
function lep_accounts.create(list)
	local to_create, created, refused = accounts.plan(list, {
		find = lep_accounts.find,
		has_password = has_password,
	})
	local handler = core.get_auth_handler()
	for _, entry in ipairs(to_create) do
		-- The engine gives a new account the default privileges.
		handler.create_auth(entry.name, core.get_password_hash(entry.name, entry.password))
		if handler.get_auth(entry.name) then
			created[#created + 1] = entry.name
			core.log("action", "[lep_accounts] account " .. entry.name .. " created")
		else
			refused[#refused + 1] = entry.name
		end
	end
	return created, refused
end

--- Sets the password of an ordinary account. An account that holds more
-- than every new player gets, a teacher or an admin, is refused: nobody
-- takes such an account over from outside. Privileges that come from the
-- place a player is in do not count.
-- Who is in the game stays in; the new password counts from the next
-- login.
-- @return true, or false and why not: "unknown", "staff" or "invalid"
function lep_accounts.set_password(name, password)
	local exists = lep_accounts.exists(name)
	local privileges = exists and core.get_player_privs(name) or {}
	if exists and core.global_exists("lep_places") then
		-- What a student holds only because of the room they are in does
		-- not make them a teacher.
		privileges = accounts.without(privileges, lep_places.get_granted_privileges(name))
	end
	local ok, why = accounts.may_set_password(name, password, exists, privileges,
		ordinary_privileges())
	if not ok then
		core.log("warning", "[lep_accounts] password for " .. tostring(name)
			.. " not set: " .. why)
		return false, why
	end
	core.get_auth_handler().set_password(name, core.get_password_hash(name, password))
	core.log("action", "[lep_accounts] password of " .. name .. " set")
	return true
end
