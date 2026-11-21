-- The account of the admin from the settings. The world creates it at
-- its first start with a start password and notes the password in a
-- file in its own folder. Whoever runs the server reads it there. It
-- never leaves the machine: not to the backend, not into the log.
--
-- The file is removed as soon as the account has another password.

local load = lep_core.loader("lep_accounts")
local admin = load("src/admin")

-- Name of the file with the start password, in the folder of the world.
local FILE = "lep_admin_password.txt"
-- How often the world looks whether the start password is still in use.
local CHECK_INTERVAL = 30

local function path()
	return core.get_worldpath() .. "/" .. FILE
end

local function read_note()
	local file = io.open(path(), "r")
	if not file then
		return nil
	end
	local noted = file:read("*l")
	file:close()
	if type(noted) ~= "string" or noted == "" then
		return nil
	end
	return noted
end

local function write_note(password)
	return core.safe_file_write(path(), password .. "\n")
end

local function has_password(name, password)
	local entry = core.get_auth_handler().get_auth(name)
	return entry ~= nil and core.check_password_entry(name, entry.password, password)
end

local function roll()
	local source = SecureRandom()
	if not source then
		return nil
	end
	return admin.password_from(source:next_bytes(admin.bytes_needed()))
end

local function create(name)
	local password = roll()
	if not password then
		core.log("error", "[lep_accounts] cannot make a start password for the admin '"
			.. name .. "': no secure random numbers")
		return
	end
	-- The note comes first. An account whose password nobody can read
	-- would lock the admin out.
	if not write_note(password) then
		core.log("error", "[lep_accounts] cannot write " .. FILE
			.. ", so the account of the admin '" .. name .. "' is not created")
		return
	end
	local handler = core.get_auth_handler()
	handler.create_auth(name, core.get_password_hash(name, password))
	if not handler.get_auth(name) then
		os.remove(path())
		core.log("error", "[lep_accounts] cannot create the account of the admin '" .. name .. "'")
		return
	end
	core.log("action", "[lep_accounts] created the account of the admin '" .. name
		.. "'. Its start password is in " .. FILE .. " in the folder of the world")
end

--- Looks after the account of the admin: creates it if it is missing,
-- and removes the note once the start password is no longer in use.
function lep_accounts.check_admin()
	if core.is_singleplayer() then
		return
	end
	local name = core.settings:get("name")
	if not admin.is_set(name) then
		return
	end
	local noted = read_note()
	local exists = lep_accounts.exists(name)
	local still_valid = exists and noted ~= nil and has_password(name, noted)
	local action = admin.decide(name, exists, noted, still_valid)
	if action == admin.CREATE then
		create(name)
	elseif action == admin.FORGET then
		os.remove(path())
		core.log("action", "[lep_accounts] the admin '" .. name
			.. "' has a password of their own, " .. FILE .. " is removed")
	end
end

-- Accounts cannot be created while the mods are still loading. The
-- first step of the server comes before anybody can enter.
core.after(0, lep_accounts.check_admin)

core.register_on_leaveplayer(function(player)
	if player:get_player_name() == core.settings:get("name") then
		-- After the player is gone, so a changed password is stored.
		core.after(1, lep_accounts.check_admin)
	end
end)

local function check_regularly()
	if read_note() then
		lep_accounts.check_admin()
	end
	core.after(CHECK_INTERVAL, check_regularly)
end
core.after(CHECK_INTERVAL, check_regularly)
