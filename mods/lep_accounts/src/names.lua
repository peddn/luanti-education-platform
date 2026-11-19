-- Rules for display names: the name a player chooses to be shown under
-- instead of the account name. Pure Lua, no engine calls.
--
-- The state of one account is a table with
--   display     the chosen name, or nil while the account name is shown
--   changed_at  when the player chose a name last, or nil; the next
--               change is possible one period later
--   locked      true if a teacher has locked choosing a name

local names = {}

names.MIN = 2
names.MAX = 16
-- A player may choose a new name once in this time, in seconds.
names.PERIOD = 30 * 24 * 60 * 60

-- Why a name or a change is refused.
names.SHORT = "short"
names.LONG = "long"
names.CHARACTERS = "characters"
names.TAKEN = "taken"
names.LOCKED = "locked"
names.WAIT = "wait"

-- The letters beyond ASCII that are allowed, with their small form.
local SPECIAL = {
	["ä"] = "ä", ["ö"] = "ö", ["ü"] = "ü", ["ß"] = "ß",
	["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü",
}

-- Splits a text into its characters: ASCII letters and digits, the
-- special letters, and the two separators. Returns nil if anything else
-- is in it.
local function characters(text)
	local list = {}
	local index = 1
	while index <= #text do
		local one = text:sub(index, index)
		local two = text:sub(index, index + 1)
		if one:match("^[%w %-]$") then
			list[#list + 1] = one
			index = index + 1
		elseif SPECIAL[two] then
			list[#list + 1] = two
			index = index + 2
		else
			return nil
		end
	end
	return list
end

local function is_separator(character)
	return character == " " or character == "-"
end

--- Checks a text a player typed as a name. Spaces around it are cut off.
-- Allowed are letters, also umlauts and ß, digits, and single spaces and
-- hyphens between them.
-- @return the name  or  nil, why not: SHORT, LONG or CHARACTERS
function names.check(text)
	if type(text) ~= "string" then
		return nil, names.CHARACTERS
	end
	text = text:match("^%s*(.-)%s*$")
	local list = characters(text)
	if not list then
		return nil, names.CHARACTERS
	end
	if #list < names.MIN then
		return nil, names.SHORT
	end
	if #list > names.MAX then
		return nil, names.LONG
	end
	for index, character in ipairs(list) do
		if is_separator(character)
				and (index == 1 or index == #list or is_separator(list[index - 1])) then
			return nil, names.CHARACTERS
		end
	end
	return text
end

--- Returns a text in the form names are compared in: two names that
-- differ only in the case of their letters are the same name. Works for
-- account names too.
function names.fold(text)
	local folded = text:lower()
	for letter, small in pairs(SPECIAL) do
		folded = folded:gsub(letter, small)
	end
	return folded
end

--- Returns the state of an account that never chose a name.
function names.new_state()
	return { locked = false }
end

--- Repairs a state that comes from storage.
function names.normalize(state)
	local result = names.new_state()
	if type(state) ~= "table" then
		return result
	end
	if names.check(state.display) == state.display then
		result.display = state.display
	end
	if type(state.changed_at) == "number" then
		result.changed_at = state.changed_at
	end
	result.locked = state.locked == true
	return result
end

--- Returns when a player may choose a name next, or nil if right away.
function names.next_change(state, now)
	if state.changed_at and now < state.changed_at + names.PERIOD then
		return state.changed_at + names.PERIOD
	end
	return nil
end

--- Says whether a player may change anything about their name now.
-- @return true  or  false, why not (LOCKED or WAIT), and for WAIT the
--   time from which a change is possible
function names.may_change(state, now)
	if state.locked then
		return false, names.LOCKED
	end
	local from = names.next_change(state, now)
	if from then
		return false, names.WAIT, from
	end
	return true
end

--- Lets a player choose a name.
-- @param name A name that passed names.check.
-- @param is_taken Function(folded) returning true if another account
--   has this name, as account name or as display name.
-- @return new state  or  nil, why not (TAKEN, LOCKED or WAIT), and for
--   WAIT the time from which a change is possible
function names.choose(state, name, now, is_taken)
	local ok, why, from = names.may_change(state, now)
	if not ok then
		return nil, why, from
	end
	if is_taken(names.fold(name)) then
		return nil, names.TAKEN
	end
	return { display = name, changed_at = now, locked = false }
end

--- Lets a player go back to the account name. That is a change like
-- any other: not while choosing is locked, and not during the wait.
-- @return new state  or  nil, why not (LOCKED or WAIT), and for WAIT
--   the time from which a change is possible
function names.give_up(state, now)
	local ok, why, from = names.may_change(state, now)
	if not ok then
		return nil, why, from
	end
	return { changed_at = state.changed_at, locked = false }
end

--- Takes the name away, as a teacher does. The player may choose a new
-- one right away, unless choosing is locked.
function names.remove(state)
	return { locked = state.locked }
end

--- Locks or unlocks choosing a name. The name itself stays.
function names.set_locked(state, locked)
	return { display = state.display, changed_at = state.changed_at, locked = locked == true }
end

return names
