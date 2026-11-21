-- Keeps the passwords of teachers the same in all worlds.
--
-- A world stores of a password only an entry the password cannot be
-- worked out from. This file reports the entries of the teachers to the
-- backend, at the start and whenever one changed, and writes the entry
-- the backend passes on from another world. No password is ever seen
-- here, and no entry is written into a log.
--
-- Until a teacher has logged in once, the engine stores an older form
-- of entry that is as good as the password. That one never leaves the
-- world: the account is reported without it.
--
-- The backend counts the passwords of a teacher: each new one is a new
-- version. The world remembers which version it was told to write, and
-- says with every report whether the password was changed here since.
-- So an old report that arrives late never brings an old password back.

local load = lep_core.loader("lep_bridge")
local accounts = load("src/accounts")
local reports = load("src/reports")

--- Remembers that the password an account has right now is the version
-- the backend named. Does nothing without a version.
function lep_bridge._note_staff_password()
end

if not core.global_exists("lep_accounts") then
	return
end

-- Seconds between two looks at the accounts. The engine does not tell
-- when somebody changes their password.
local CHECK_INTERVAL = 30
local RECORD_PREFIX = "staff_password:"

local mod_storage = core.get_mod_storage()

local function record_of(name)
	return reports.parse_staff_password_record(mod_storage:get_string(RECORD_PREFIX .. name))
end

-- What was reported last, as one text. Kept in memory only.
local reported

local function report(always)
	local payload = reports.staff_passwords(lep_accounts.get_staff_entries(), record_of,
		core.sha256, lep_accounts.is_password_entry)
	local mark = reports.staff_passwords_mark(payload)
	if always or mark ~= reported then
		reported = mark
		lep_bridge.send(reports.EVENT_STAFF_PASSWORDS, payload)
	end
end

function lep_bridge._note_staff_password(name, version)
	if not version then
		return
	end
	for _, account in ipairs(lep_accounts.get_staff_entries()) do
		if account.name == name then
			mod_storage:set_string(RECORD_PREFIX .. name,
				reports.staff_password_record(version, core.sha256(account.entry)))
		end
	end
	core.after(0, report, false)
end

-- At every start the whole list goes out, even an empty one: that is
-- how the backend learns which teachers a new world is missing.
core.register_on_mods_loaded(function()
	core.after(0, report, true)
end)

lep_bridge._add_state(function()
	report(true)
end)

local since_check = 0
core.register_globalstep(function(dtime)
	since_check = since_check + dtime
	if since_check >= CHECK_INTERVAL then
		since_check = 0
		report(false)
	end
end)

lep_bridge.register_job(reports.JOB_SET_PASSWORD_ENTRY, function(payload)
	local name, entry, version = accounts.parse_entry(payload)
	if not name then
		return false, "the order cannot be read"
	end
	local ok, changed = lep_accounts.set_password_entry(name, entry)
	if not ok then
		-- A fixed word: unknown, staff, ordinary or invalid.
		return false, changed
	end
	-- Nobody ordered this: the teacher changed the password in another
	-- world. It stands under their own account.
	if changed and core.global_exists("lep_desk") then
		lep_desk.record(name, "web:sync_password", name)
	end
	lep_bridge._note_staff_password(name, version)
	return true, "set"
end)
