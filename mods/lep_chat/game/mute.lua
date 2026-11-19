-- Muting: a teacher takes the chat away from single students.
--
-- A muted player loses the engine's shout privilege, which closes chat,
-- private messages and /me in one go. The list of the players muted here
-- says who gets it back.

local load = lep_core.loader("lep_chat")
local chat = load("src/chat")
local S = core.get_translator("lep_chat")

local STORAGE_KEY = "mutes"
local mod_storage = core.get_mod_storage()
local mutes = chat.new_mutes(core.deserialize(mod_storage:get_string(STORAGE_KEY)))

lep_chat.PRIV_MUTE = "lep_mute_players"

core.register_privilege(lep_chat.PRIV_MUTE, {
	description = "Can mute students in the chat",
	give_to_singleplayer = false,
	give_to_admin = true,
})

local function save()
	mod_storage:set_string(STORAGE_KEY, core.serialize(mutes:data()))
end

local function set_shout(player_name, value)
	local privs = core.get_player_privs(player_name)
	privs.shout = value or nil
	core.set_player_privs(player_name, privs)
end

--- Mutes a player. Returns false if the player is muted already or could
-- not write in the chat anyway.
function lep_chat.mute(player_name)
	local can_speak = core.check_player_privs(player_name, { shout = true })
	if not mutes:mute(player_name, can_speak) then
		return false
	end
	save()
	set_shout(player_name, false)
	core.log("action", "[lep_chat] " .. player_name .. " was muted")
	lep_desk.refresh()
	return true
end

--- Lifts the mute of a player. Returns false if the player was not muted
-- here.
function lep_chat.unmute(player_name)
	if not mutes:unmute(player_name) then
		return false
	end
	save()
	set_shout(player_name, true)
	core.log("action", "[lep_chat] " .. player_name .. " is no longer muted")
	lep_desk.refresh()
	return true
end

--- Returns true if a teacher muted this player.
function lep_chat.is_muted(player_name)
	return mutes:is_muted(player_name)
end

-- Lifts all mutes, for the moments when no teacher is there.
local function unmute_all()
	for _, player_name in ipairs(mutes:data()) do
		lep_chat.unmute(player_name)
		if core.get_player_by_name(player_name) then
			core.chat_send_player(player_name, S("No teacher is online any more. "
				.. "You may write in the chat again."))
		end
	end
end

-- A mute never outlasts the teacher: a student who was forgotten could
-- not talk for days. After a start of the server no teacher is online.
lep_desk.register_on_unattended(unmute_all)
core.register_on_mods_loaded(unmute_all)

lep_desk.register_student_note(function(student)
	return mutes:is_muted(student) and S("muted") or nil
end)

local GROUP = S("Chat")

lep_desk.register_action("lep_chat:mute", {
	title = S("Mute"),
	privilege = lep_chat.PRIV_MUTE,
	group = GROUP,
	run = function(_, targets)
		local count = 0
		for _, student in ipairs(targets) do
			if lep_chat.mute(student) then
				count = count + 1
				core.chat_send_player(student,
					S("Your teacher has muted you. You cannot write in the chat."))
			end
		end
		return S("Muted: @1 of @2", count, #targets)
	end,
})

lep_desk.register_action("lep_chat:unmute", {
	title = S("Unmute"),
	privilege = lep_chat.PRIV_MUTE,
	group = GROUP,
	run = function(_, targets)
		local count = 0
		for _, student in ipairs(targets) do
			if lep_chat.unmute(student) then
				count = count + 1
				core.chat_send_player(student, S("You may write in the chat again."))
			end
		end
		return S("Unmuted: @1 of @2", count, #targets)
	end,
})

-- An account that is removed is taken off the list of muted players.
lep_core.register_on_forget_account(function(account)
	if mutes:unmute(account) then
		save()
	end
end)
