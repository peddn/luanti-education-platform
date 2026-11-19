-- Rules for accounts. Pure Lua, no engine calls.

local accounts = {}

-- Longest name the engine takes (tried with Luanti 5.18). The backend
-- stays one below.
accounts.MAX_NAME = 20

--- Returns true if a text is a name the engine takes for a player.
function accounts.is_name(name)
	return type(name) == "string" and #name >= 1 and #name <= accounts.MAX_NAME
		and name:find("^[%w_%-]+$") ~= nil
end

--- Decides what to do with each account that shall be created.
-- @param list List of tables with name and password.
-- @param world Table of functions about this world:
--   find(name)             returns the name of an existing account that
--                          equals `name` in any letter case, or nil
--   has_password(name, pw) returns true if the account has this password
-- @return to_create (list of name and password), created (names that
--   exist already with exactly this password, from an earlier run of the
--   same order), refused (names)
function accounts.plan(list, world)
	local to_create, created, refused = {}, {}, {}
	local seen = {}
	for _, entry in ipairs(list) do
		local name, password = entry.name, entry.password
		local key = type(name) == "string" and name:lower() or nil
		if not accounts.is_name(name) or type(password) ~= "string" or password == ""
				or seen[key] then
			if type(name) == "string" and name ~= "" then
				refused[#refused + 1] = name
			end
		else
			seen[key] = true
			local existing = world.find(name)
			if not existing then
				to_create[#to_create + 1] = { name = name, password = password }
			elseif existing == name and world.has_password(name, password) then
				-- The order arrived before and was done. An account of
				-- somebody else would not have this password.
				created[#created + 1] = name
			else
				-- Taken. The account of somebody else is never touched.
				refused[#refused + 1] = name
			end
		end
	end
	return to_create, created, refused
end

--- Reads a list of privileges as the settings write it: "interact, shout".
-- @return Set of privilege names.
function accounts.privilege_set(text)
	local set = {}
	for name in tostring(text or ""):gmatch("[^,%s]+") do
		set[name] = true
	end
	return set
end

--- Returns a set of privileges without the ones in another set.
function accounts.without(privileges, taken)
	local rest = {}
	for name, held in pairs(privileges) do
		if held and not taken[name] then
			rest[name] = true
		end
	end
	return rest
end

-- What a teacher gets when the school administration creates their
-- account: the bundle "teacher" of the concept, section 10.5. Privileges
-- a world does not know are left out there.
accounts.TEACHER_PRIVILEGES = {
	"lep_view_players", "lep_send_players", "lep_watch_players", "lep_set_attention",
	"lep_set_mode", "lep_set_time", "lep_mute_players", "lep_place_quest_chest",
	"lep_web_access",
}

-- Privileges that make an account one nobody touches from outside: the
-- school administration and whoever runs the server.
local PROTECTING = { "lep_manage_school", "privs", "server" }

--- Returns true if an account is never touched from outside, whoever
-- asks: the admin from the settings, the school administration and
-- whoever can hand out privileges or run the server. The backend stands
-- in the net; who takes it over shall not get these accounts.
-- @param admin Name of the admin from the settings, or nil.
function accounts.is_protected(name, privileges, admin)
	if type(admin) == "string" and admin ~= "" and name == admin then
		return true
	end
	for _, privilege in ipairs(PROTECTING) do
		if privileges[privilege] then
			return true
		end
	end
	return false
end

--- Decides whether an order from outside may touch an account, as far
-- as its privileges go.
-- @param is_ordinary True if it holds nothing but what every new player
--   gets.
-- @param staff_allowed True if the order says it is meant for a teacher:
--   only the school administration gives such orders.
-- @param is_protected See accounts.is_protected.
function accounts.may_touch(is_ordinary, staff_allowed, is_protected)
	if is_protected then
		return false
	end
	return is_ordinary or staff_allowed == true
end

--- Returns true if an account holds nothing but what every new player
-- gets. Only such an account may get a password from outside: whoever
-- holds more is a teacher or an admin, and an order that names them is a
-- mistake or an attack.
-- @param privileges Set of the privileges the account holds.
-- @param ordinary Set of the privileges every new player gets.
function accounts.is_ordinary(privileges, ordinary)
	for name, held in pairs(privileges) do
		if held and not ordinary[name] then
			return false
		end
	end
	return true
end

-- Why a password is not set.
accounts.UNKNOWN = "unknown"
accounts.STAFF = "staff"
accounts.INVALID = "invalid"

--- Decides whether the password of an account may be set from outside.
-- @param exists True if there is exactly this account.
-- @param staff_allowed True if the order is meant for a teacher.
-- @param admin Name of the admin from the settings, or nil.
-- @return true, or false and why not: UNKNOWN, STAFF or INVALID
function accounts.may_set_password(name, password, exists, privileges, ordinary,
		staff_allowed, admin)
	if not accounts.is_name(name) or type(password) ~= "string" or password == "" then
		return false, accounts.INVALID
	elseif not exists then
		return false, accounts.UNKNOWN
	elseif not accounts.may_touch(accounts.is_ordinary(privileges, ordinary), staff_allowed,
			accounts.is_protected(name, privileges, admin)) then
		return false, accounts.STAFF
	end
	return true
end

--- Decides whether somebody may enter the world with a name. The world
-- is closed: only names with an account get in. The admin is the one
-- exception, or nobody could ever enter a new world.
-- @param exists True if there is an account with this name.
-- @param admin Name of the admin from the settings, or nil.
function accounts.may_join(name, exists, admin)
	return exists == true or (type(admin) == "string" and admin ~= "" and name == admin)
end

return accounts
