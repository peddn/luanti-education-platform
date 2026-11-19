-- The window in which a player chooses their display name. It is opened
-- from the name sign of their room in the lobby.

local S = core.get_translator("lep_accounts")
local formspec = lep_core.formspec

local FORM = "lep_accounts:name"
local WIDTH, HEIGHT = 9, 6.2
local REFUSALS = lep_accounts.NAME_REFUSALS

-- Players who have the window open. Fields from anybody else are ignored.
local open = {}

local function date(time)
	return os.date("%d.%m.%Y", time)
end

-- Says in words why a name was refused.
local function explain(why, from)
	if why == REFUSALS.SHORT then
		return S("The name is too short. It needs at least @1 characters.", lep_accounts.NAME_MIN)
	elseif why == REFUSALS.LONG then
		return S("The name is too long. It may have @1 characters at most.", lep_accounts.NAME_MAX)
	elseif why == REFUSALS.TAKEN then
		return S("Somebody else has this name already.")
	elseif why == REFUSALS.LOCKED then
		return S("A teacher has locked choosing a name for you.")
	elseif why == REFUSALS.WAIT then
		return S("You can choose a new name from @1.", date(from))
	end
	return S("Only letters, digits, and single spaces and hyphens between them are allowed.")
end

-- A window that only says why nothing can be changed now. Offering a
-- field and buttons that will not work would only confuse.
local function show_closed(player_name, reason)
	local fs = formspec.new(WIDTH, 3.9)
	fs:label(0.5, 0.6, S("Your display name"))
	fs:label(0.5, 1.2, S("Others see you as: @1", lep_accounts.get_display_name(player_name)))
	-- A text area without a name only shows its text, and breaks lines.
	fs:element("textarea", { 0.5, 1.6 }, { WIDTH - 1, 1.1 }, "", "", formspec.escape(reason))
	fs:button_exit(WIDTH - 2, 2.7, 1.5, 0.8, "close", S("Close"))
	open[player_name] = true
	core.show_formspec(player_name, FORM, fs:build())
end

local function show(player_name, typed, message)
	local state = lep_accounts.get_display_state(player_name)
	if state.locked then
		return show_closed(player_name, explain(REFUSALS.LOCKED))
	elseif state.next_change then
		return show_closed(player_name, explain(REFUSALS.WAIT, state.next_change))
	end

	local fs = formspec.new(WIDTH, HEIGHT)
	fs:label(0.5, 0.6, S("Your display name"))
	fs:label(0.5, 1.2, S("Others see you as: @1", lep_accounts.get_display_name(player_name)))
	local hint = S("You can choose a new name once in 30 days.") .. " "
		.. S("Until then nothing can be changed. Your teachers see every name.")
	-- A text area without a name only shows its text, and breaks lines.
	fs:element("textarea", { 0.5, 1.6 }, { WIDTH - 1, 1.1 }, "", "",
		formspec.escape(message or hint))

	fs:field(0.5, 3.3, WIDTH - 1, 0.8, "name", S("New name"), typed or state.display or "")
	fs:submit_on_enter("name")
	fs:button(0.5, 4.5, 2.5, 0.8, "apply", S("Apply"))
	if state.display then
		fs:button(3.2, 4.5, 3.6, 0.8, "give_up", S("Back to account name"))
	end
	fs:button_exit(WIDTH - 2, 4.5, 1.5, 0.8, "close", S("Close"))
	open[player_name] = true
	core.show_formspec(player_name, FORM, fs:build())
end

local function close(player_name, message)
	open[player_name] = nil
	core.close_formspec(player_name, FORM)
	core.chat_send_player(player_name, message)
end

--- Opens the window for choosing a display name for a player.
function lep_accounts.show_name_window(player_name)
	if core.get_player_by_name(player_name) then
		show(player_name)
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	local player_name = player:get_player_name()
	if not open[player_name] then
		return true
	end

	-- A player only ever changes their own name: the account comes from
	-- the connection, never from the window. The rules are checked again
	-- by lep_accounts.
	-- When the change is made the window closes, and the chat says what
	-- counts now. It stays open only to say why a name does not fit.
	if fields.give_up then
		local ok, why, from = lep_accounts.give_up_display_name(player_name)
		if ok then
			close(player_name, S("You are shown under your account name again."))
		else
			show_closed(player_name, explain(why, from))
		end
	elseif fields.apply or fields.key_enter_field == "name" then
		local typed = type(fields.name) == "string" and fields.name:sub(1, 200) or ""
		local ok, why, from = lep_accounts.choose_display_name(player_name, typed)
		if ok then
			close(player_name, S("Your display name is now: @1",
				lep_accounts.get_display_name(player_name)))
		elseif why == REFUSALS.LOCKED or why == REFUSALS.WAIT then
			show_closed(player_name, explain(why, from))
		else
			show(player_name, typed, explain(why, from))
		end
	elseif fields.quit then
		open[player_name] = nil
	end
	return true
end)

core.register_on_leaveplayer(function(player)
	open[player:get_player_name()] = nil
end)
