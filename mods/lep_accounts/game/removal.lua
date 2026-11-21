-- Removing an account on request: everything this world knows about it
-- goes, see the concept, section 12.
--
-- Every mod deletes its own data: it registers a function for that
-- with lep_core.register_on_forget_account. The account itself goes
-- last: if anything fails on the way, it is still there and the removal
-- can be ordered again.

local load = lep_core.loader("lep_accounts")
local accounts = load("src/accounts")
local removal = load("src/removal")
local S = core.get_translator("lep_accounts")

-- Seconds between two looks whether a disconnected player is gone, and
-- how often to look.
local WAIT_STEP = 0.2
local WAIT_STEPS = 25

lep_accounts.REMOVAL_REFUSALS = {
	UNKNOWN = removal.UNKNOWN, STAFF = removal.STAFF, USED = removal.USED,
	BUSY = removal.BUSY, ONLINE = removal.ONLINE, INCOMPLETE = removal.INCOMPLETE,
}

local removing = {}

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_accounts] callback for " .. event_name .. " failed: "
		.. tostring(err))
end)

--- Calls listener(account, by) after an account was removed with
-- everything the world knew about it. by is the account name of who
-- ordered it, or nil. Who has to delete own data registers with
-- lep_core.register_on_forget_account instead: this is only the news.
lep_accounts.register_on_removed = dispatcher:registrar("removed")

--- Returns true while an account is being removed. Nobody may join
-- under its name then.
function lep_accounts.is_being_removed(name)
	return removing[name] == true
end

--- Returns true if somebody has ever logged in with an account.
function lep_accounts.was_used(name)
	local entry = core.get_auth_handler().get_auth(name)
	return entry ~= nil and removal.was_used(entry.last_login)
end

-- Returns true if an order from outside may remove this account: an
-- ordinary one, or a teacher if the order says so. What a student holds
-- only because of the room they are in does not count. The admin and
-- the school administration are never removed this way.
local function may_touch(name, staff_allowed)
	local privileges = core.get_player_privs(name)
	if core.global_exists("lep_places") then
		privileges = accounts.without(privileges, lep_places.get_granted_privileges(name))
	end
	local ordinary = accounts.is_ordinary(privileges,
		accounts.privilege_set(core.settings:get("default_privs")))
	return accounts.may_touch(ordinary, staff_allowed,
		accounts.is_protected(name, privileges, core.settings:get("name")))
end

-- Deletes everything about an account whose player is not in the game.
-- @return true, or false if something could not be deleted
local function delete(name)
	local failed = lep_core.forget_account(name)
	lep_accounts._forget_display_name(name)

	local _, unwritten = lep_core.protocols.remove_account(name)
	failed = failed + unwritten

	-- What the engine keeps about the player: position, inventory and
	-- metadata. 0 is done, 1 means there was nothing, 2 that the player
	-- is in the game.
	if core.remove_player(name) == 2 then
		failed = failed + 1
	end

	if failed > 0 then
		return false
	end
	if not core.remove_player_auth(name) then
		return false
	end
	lep_accounts._set_managed(name, false)
	return true
end

--- Removes an account and everything this world knows about it. A
-- player who is in the game is told and disconnected first, so the
-- answer comes a moment later.
-- @param options Table with:
--   only_unused  true if only an account nobody ever logged in with may
--                be removed
--   staff        true if the order is meant for a teacher: only the
--                school administration gives it. Nobody removes
--                themselves.
--   by           account name of who ordered it, for the log
-- @param callback Optional function(ok, why). why is one of
--   lep_accounts.REMOVAL_REFUSALS.
function lep_accounts.remove(name, options, callback)
	options = options or {}
	callback = callback or function() end

	local exists = lep_accounts.exists(name)
	if exists and removing[name] then
		callback(false, removal.BUSY)
		return
	end
	local allowed = exists and options.by ~= name
		and may_touch(name, options.staff == true)
	local ok, why = removal.may_remove(exists, allowed,
		exists and lep_accounts.was_used(name), options.only_unused == true)
	if not ok then
		core.log("warning", "[lep_accounts] account " .. tostring(name)
			.. " not removed: " .. why)
		callback(false, why)
		return
	end

	removing[name] = true
	local function finish()
		local done = delete(name)
		removing[name] = nil
		if done then
			core.log("action", "[lep_accounts] account " .. name .. " removed"
				.. (options.by and " by " .. options.by or ""))
			dispatcher:emit("removed", name, options.by)
			callback(true)
		else
			core.log("error", "[lep_accounts] account " .. name
				.. " not removed: something could not be deleted")
			callback(false, removal.INCOMPLETE)
		end
	end

	if not core.get_player_by_name(name) then
		finish()
		return
	end

	local language = core.get_player_information(name).lang_code
	core.disconnect_player(name, core.get_translated_string(language ~= "" and language or "de",
		S("This account has been deleted. Please talk to your teacher.")))
	-- The engine lets go of the player a moment later.
	local function wait(steps_left)
		if not core.get_player_by_name(name) then
			finish()
		elseif steps_left <= 0 then
			removing[name] = nil
			core.log("error", "[lep_accounts] account " .. name
				.. " not removed: its player is still in the game")
			callback(false, removal.ONLINE)
		else
			core.after(WAIT_STEP, wait, steps_left - 1)
		end
	end
	core.after(WAIT_STEP, wait, WAIT_STEPS)
end
