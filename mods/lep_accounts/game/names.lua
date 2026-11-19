-- Display names: the name a player chooses to be shown under. Nobody
-- approves it. Every change is written into a protocol, and a teacher
-- can take a name away and lock choosing. The rules are in src/names.lua.
--
-- Other mods ask lep_accounts.get_display_name for the name to show and
-- never keep it: protocols and storage always use the account name.

local load = lep_core.loader("lep_accounts")
local names = load("src/names")
local storage = load("game/name_storage")

local protocol = lep_core.protocols.open("names", { "account", "action", "name", "by" })

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_accounts] callback for " .. event_name .. " failed: "
		.. tostring(err))
end)

-- What happened to a name, for listeners and the protocol.
lep_accounts.NAME_CHOSEN = "chosen"      -- by the player
lep_accounts.NAME_GIVEN_UP = "given_up"  -- by the player, back to the account name
lep_accounts.NAME_REMOVED = "removed"    -- taken away
lep_accounts.NAME_LOCKED = "locked"
lep_accounts.NAME_UNLOCKED = "unlocked"

-- Reasons a name is refused, see src/names.lua.
lep_accounts.NAME_REFUSALS = {
	SHORT = names.SHORT, LONG = names.LONG, CHARACTERS = names.CHARACTERS,
	TAKEN = names.TAKEN, LOCKED = names.LOCKED, WAIT = names.WAIT,
}
lep_accounts.NAME_MIN = names.MIN
lep_accounts.NAME_MAX = names.MAX

-- All states, by account name, and who has which name, by the folded
-- name. Both are filled from storage once.
local states = {}
local owners = {}
for _, account in ipairs(storage.accounts()) do
	local state = names.normalize(storage.load(account))
	states[account] = state
	if state.display then
		owners[names.fold(state.display)] = account
	end
end

local function state_of(account)
	return states[account] or names.new_state()
end

local function store(account, state, action, by)
	local old = state_of(account)
	if old.display then
		owners[names.fold(old.display)] = nil
	end
	if state.display then
		owners[names.fold(state.display)] = account
	end
	states[account] = state
	storage.save(account, state)
	-- For a name that was taken away the protocol keeps which one it was.
	protocol:append({
		account = account,
		action = action,
		name = state.display or old.display or "",
		by = by or account,
	})
	core.log("action", "[lep_accounts] display name of " .. account .. ": " .. action
		.. (by and " by " .. by or ""))
	dispatcher:emit("display_name_changed", account, action)
end

--- Returns the name a player is shown under: the display name they
-- chose, or the account name.
function lep_accounts.get_display_name(account)
	return state_of(account).display or account
end

--- Returns what is known about the display name of an account: a table
-- with display (nil while the account name is shown), changed_at (when
-- the player chose a name last, or nil), locked, and next_change (time
-- from which a new name can be chosen, nil if now).
function lep_accounts.get_display_state(account)
	local state = state_of(account)
	return {
		display = state.display,
		changed_at = state.changed_at,
		locked = state.locked,
		next_change = names.next_change(state, os.time()),
	}
end

--- Returns the accounts that have a display name or a lock, sorted.
function lep_accounts.get_display_accounts()
	local list = {}
	for account, state in pairs(states) do
		if state.display or state.locked then
			list[#list + 1] = account
		end
	end
	table.sort(list)
	return list
end

-- A name is taken if another account has it, as account name or as
-- display name. The case of letters makes no difference.
local function taken_for(account)
	return function(folded)
		local owner = owners[folded]
		if owner and owner ~= account then
			return true
		end
		local other = lep_accounts.find(folded)
		return other ~= nil and other ~= account
	end
end

--- Lets a player choose a display name. The own account name means
-- going back to it.
-- @return true  or  false, why not (one of lep_accounts.NAME_REFUSALS),
--   and for WAIT the time from which a change is possible
function lep_accounts.choose_display_name(account, text)
	if not lep_accounts.exists(account) then
		return false, names.CHARACTERS
	end
	local name, why = names.check(text)
	if not name then
		return false, why
	end
	if name == account then
		lep_accounts.give_up_display_name(account)
		return true
	end
	local state = state_of(account)
	if state.display == name then
		return true
	end
	local new_state, refusal, from = names.choose(state, name, os.time(), taken_for(account))
	if not new_state then
		return false, refusal, from
	end
	store(account, new_state, lep_accounts.NAME_CHOSEN)
	return true
end

--- Lets a player go back to the account name. That is always possible,
-- also during the wait and while choosing a name is locked.
function lep_accounts.give_up_display_name(account)
	local state = state_of(account)
	if state.display then
		store(account, names.give_up(state), lep_accounts.NAME_GIVEN_UP)
	end
end

--- Takes the display name of an account away.
-- @param by Account name of who did it, for the protocol.
-- @return true if there was a name
function lep_accounts.remove_display_name(account, by)
	local state = state_of(account)
	if not state.display then
		return false
	end
	store(account, names.remove(state), lep_accounts.NAME_REMOVED, by)
	return true
end

--- Locks or unlocks choosing a display name for an account. The name
-- the account has stays.
-- @param by Account name of who did it, for the protocol.
function lep_accounts.set_display_locked(account, locked, by)
	local state = state_of(account)
	if state.locked ~= (locked == true) then
		store(account, names.set_locked(state, locked),
			locked and lep_accounts.NAME_LOCKED or lep_accounts.NAME_UNLOCKED, by)
	end
end

--- Forgets when a player chose a name last, so they can choose again.
-- For tests only.
function lep_accounts._reset_display_wait(account)
	local state = state_of(account)
	states[account] = { display = state.display, locked = state.locked }
	storage.save(account, states[account])
end

-- Forgets everything about the display name of an account that is being
-- removed. Nothing is written into the protocol and nobody is told: the
-- account is on its way out.
function lep_accounts._forget_display_name(account)
	local state = states[account]
	if state and state.display and owners[names.fold(state.display)] == account then
		owners[names.fold(state.display)] = nil
	end
	states[account] = nil
	storage.remove(account)
end

--- Calls listener(account, action) after something happened to the
-- display name of an account. action is one of lep_accounts.NAME_...;
-- lep_accounts.get_display_name gives the name that counts now.
lep_accounts.register_on_display_name_changed = dispatcher:registrar("display_name_changed")

-- An account that is created with the name somebody chose as display
-- name keeps its name: the display name gives way.
function lep_accounts._release_name(account_name)
	local owner = owners[names.fold(account_name)]
	if owner and owner ~= account_name then
		lep_accounts.remove_display_name(owner, account_name)
	end
end
