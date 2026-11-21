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

local function has_entry(name, wanted)
	local entry = core.get_auth_handler().get_auth(name)
	return entry ~= nil and entry.password == wanted
end

-- The privileges every new player gets. An account that holds nothing
-- else is an ordinary one.
local function ordinary_privileges()
	return accounts.privilege_set(core.settings:get("default_privs"))
end

-- The privileges an account holds by itself. What a student holds only
-- because of the room they are in does not make them a teacher.
local function own_privileges(name)
	local privileges = core.get_player_privs(name)
	if core.global_exists("lep_places") then
		privileges = accounts.without(privileges, lep_places.get_granted_privileges(name))
	end
	return privileges
end

--- Creates accounts with a start password each.
-- An account that exists is never touched: its name is refused. Only an
-- account that exists with exactly this password counts as created,
-- because then the same order was done before.
-- @param list List of tables with name and password. A teacher may
--   come with `entry` instead: what another world stores of their
--   password. Then they have the same password here.
-- @param options Optional table. With teacher = true the new accounts
--   get the privileges of the bundle for teachers on top, as far as this
--   world knows them. An account that existed before gets nothing.
-- @return created (list of names), refused (list of names)
function lep_accounts.create(list, options)
	local to_create, created, refused = accounts.plan(list, {
		find = lep_accounts.find,
		has_password = has_password,
		has_entry = has_entry,
	}, options ~= nil and options.teacher == true)
	local handler = core.get_auth_handler()
	for _, entry in ipairs(to_create) do
		-- The engine gives a new account the default privileges.
		handler.create_auth(entry.name,
			entry.entry or core.get_password_hash(entry.name, entry.password))
		if handler.get_auth(entry.name) then
			if options and options.teacher then
				local privileges = core.get_player_privs(entry.name)
				for _, privilege in ipairs(accounts.TEACHER_PRIVILEGES) do
					if core.registered_privileges[privilege] then
						privileges[privilege] = true
					end
				end
				core.set_player_privs(entry.name, privileges)
			end
			lep_accounts._release_name(entry.name)
			created[#created + 1] = entry.name
			core.log("action", "[lep_accounts] account " .. entry.name .. " created"
				.. (options and options.teacher and " as a teacher" or ""))
		else
			refused[#refused + 1] = entry.name
		end
	end
	return created, refused
end

--- Sets the password of an ordinary account. An account that holds more
-- than every new player gets is refused, unless the order is meant for
-- a teacher (options.staff): then only the admin and the school
-- administration are refused. Nobody takes those over from outside.
-- Privileges that come from the place a player is in do not count.
-- Who is in the game stays in; the new password counts from the next
-- login.
-- @return true, or false and why not: "unknown", "staff" or "invalid"
function lep_accounts.set_password(name, password, options)
	local exists = lep_accounts.exists(name)
	local privileges = exists and own_privileges(name) or {}
	local ok, why = accounts.may_set_password(name, password, exists, privileges,
		ordinary_privileges(), options ~= nil and options.staff == true,
		core.settings:get("name"))
	if not ok then
		core.log("warning", "[lep_accounts] password for " .. tostring(name)
			.. " not set: " .. why)
		return false, why
	end
	core.get_auth_handler().set_password(name, core.get_password_hash(name, password))
	core.log("action", "[lep_accounts] password of " .. name .. " set")
	return true
end

--- Writes what another world stores of the password of a teacher, so
-- the teacher has the same password here. The password itself is not
-- known and cannot be worked out. Refused for the admin, for whoever
-- can hand out privileges or run the server, and for students.
-- Who is in the game stays in.
-- @return true and whether something changed, or false and why not:
--   "unknown", "staff", "ordinary" or "invalid"
function lep_accounts.set_password_entry(name, entry)
	local exists = lep_accounts.exists(name)
	local ok, why = accounts.may_set_entry(name, entry, exists,
		exists and own_privileges(name) or {}, ordinary_privileges(),
		core.settings:get("name"))
	if not ok then
		core.log("warning", "[lep_accounts] password of " .. tostring(name)
			.. " not taken over: " .. why)
		return false, why
	end
	if has_entry(name, entry) then
		return true, false
	end
	core.get_auth_handler().set_password(name, entry)
	core.log("action", "[lep_accounts] password of " .. name .. " taken over")
	return true, true
end

--- Returns true if a text is an entry of a password that may be passed
-- on to another world: the password cannot be worked out from it, and
-- nobody can log in with it. A password that was set in the world as
-- plain text, by a command or by an order with a start password, is
-- stored in an older form that is as good as the password itself.
function lep_accounts.is_password_entry(text)
	return accounts.is_entry(text)
end

--- Returns what this world stores of the passwords of its teachers:
-- a list of tables with name and entry, sorted by name. The admin and
-- whoever can hand out privileges or run the server are never in it,
-- and no student is. Not every entry may leave the world: see
-- lep_accounts.is_password_entry.
function lep_accounts.get_staff_entries()
	local handler = core.get_auth_handler()
	local ordinary, admin = ordinary_privileges(), core.settings:get("name")
	local names = {}
	for name in handler.iterate() do
		names[#names + 1] = name
	end
	table.sort(names)
	local list = {}
	for _, name in ipairs(names) do
		local entry = handler.get_auth(name)
		if entry and accounts.is_staff(name, own_privileges(name), ordinary, admin) then
			list[#list + 1] = { name = name, entry = entry.password }
		end
	end
	return list
end
