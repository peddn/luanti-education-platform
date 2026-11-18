-- Writes down what is said: chat, private messages, /me and sign texts.
-- The protocols are kept and deleted like all others, see the concept,
-- section 12.

local load = lep_core.loader("lep_chat")
local chat = load("src/chat")
local S = core.get_translator("lep_chat")

local chat_protocol = lep_core.protocols.open("chat",
	{ "account", "kind", "recipient", "text" })
local sign_protocol = lep_core.protocols.open("signs", { "account", "pos", "text" })

lep_chat.KIND_CHAT = chat.KIND_CHAT
lep_chat.KIND_PRIVATE = chat.KIND_PRIVATE
lep_chat.KIND_ACTION = chat.KIND_ACTION

local function can_speak(player_name)
	return core.check_player_privs(player_name, { shout = true })
end

-- Players who are deaf neither send nor receive: no chat, no private
-- messages, no commands. The attention mode uses this. The list lives in
-- memory; whoever makes a player deaf does it again after a restart.
local deaf = {}

--- Makes a player deaf or lifts it.
function lep_chat.set_deaf(player_name, is_deaf)
	deaf[player_name] = is_deaf and true or nil
end

--- Returns true if a player is deaf.
function lep_chat.is_deaf(player_name)
	return deaf[player_name] == true
end

-- Sends a line to everybody who is not deaf.
local function send_to_hearing(line)
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if not deaf[name] then
			core.chat_send_player(name, line)
		end
	end
end

-- The name others see a player under: the display name they chose.
local function shown(player_name)
	if core.global_exists("lep_accounts") then
		return lep_accounts.get_display_name(player_name)
	end
	return player_name
end

-- Messages to everybody. Commands never arrive here, the engine handles
-- them first. A player without the shout privilege is turned away by the
-- engine right after this, so their message is not written down.
core.register_on_chat_message(function(player_name, message)
	if message:sub(1, 1) == "/" then
		return false
	end
	if deaf[player_name] then
		core.chat_send_player(player_name, S("You cannot write in the chat right now."))
		return true
	end
	if not can_speak(player_name) then
		return false
	end
	chat_protocol:append({ account = player_name, kind = chat.KIND_CHAT, text = message })
	-- The message is sent here and not by the engine, for two reasons:
	-- the engine cannot leave out single players, and it would show the
	-- account name. The log keeps the account name, like the protocol.
	core.log("action", "CHAT: " .. core.format_chat_message(player_name, message))
	send_to_hearing(core.format_chat_message(shown(player_name), message))
	return true
end)

-- A deaf player uses no commands either: /msg and /me would get around
-- the lock, and nothing else is of use in that moment.
core.register_on_chatcommand(function(player_name)
	if deaf[player_name] then
		core.chat_send_player(player_name, S("You cannot use commands right now."))
		return true
	end
	return false
end)

-- The engine's own commands for private messages and actions are kept as
-- they are. What went through is written down.
local function record_command(command, on_success)
	local def = core.registered_chatcommands[command]
	if not def then
		return
	end
	local old_func = def.func
	core.override_chatcommand(command, {
		func = function(player_name, param)
			local ok, text = old_func(player_name, param)
			if ok then
				on_success(player_name, param)
			end
			return ok, text
		end,
	})
end

-- A private message to a deaf player is turned away, and /me reaches
-- only those who may hear.
do
	local msg = core.registered_chatcommands.msg
	if msg then
		local old_func = msg.func
		core.override_chatcommand("msg", {
			func = function(player_name, param)
				local recipient = chat.parse_private(param)
				if recipient and deaf[recipient] then
					return false, S("@1 cannot be reached right now.", recipient)
				end
				return old_func(player_name, param)
			end,
		})
	end
	if core.registered_chatcommands.me then
		core.override_chatcommand("me", {
			func = function(player_name, param)
				send_to_hearing("* " .. shown(player_name) .. " " .. param)
				return true
			end,
		})
	end
end

record_command("msg", function(player_name, param)
	local recipient, message = chat.parse_private(param)
	if recipient then
		chat_protocol:append({ account = player_name, kind = chat.KIND_PRIVATE,
			recipient = recipient, text = message })
	end
end)

record_command("me", function(player_name, param)
	chat_protocol:append({ account = player_name, kind = chat.KIND_ACTION, text = param })
end)

-- Sign texts are readable for everybody, like chat. signs_lib sends the
-- text of a sign through this window.
if core.get_modpath("signs_lib") then
	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname == "signs_lib:sign" and fields.text and fields.ok then
			sign_protocol:append({
				account = player:get_player_name(),
				pos = player:get_meta():get_string("signslib:pos"),
				text = fields.text,
			})
		end
		return false
	end)
end

-- Everybody is told that the chat is recorded.
core.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	core.after(2, function()
		if core.get_player_by_name(player_name) then
			core.chat_send_player(player_name,
				S("Note: chat, private messages and sign texts are recorded."))
		end
	end)
end)

--- Returns the last entries of the chat protocol, oldest first, each with
-- time, account, kind, recipient and text.
-- @param player_name Optional: only what this player wrote or received.
function lep_chat.get_log(player_name, limit)
	return chat_protocol:read(player_name and function(record)
		return record.account == player_name or record.recipient == player_name
	end or nil, limit)
end

--- Returns the last entries of the sign protocol, oldest first, each with
-- time, account, pos and text.
function lep_chat.get_sign_log(player_name, limit)
	return sign_protocol:read(player_name and function(record)
		return record.account == player_name
	end or nil, limit)
end
