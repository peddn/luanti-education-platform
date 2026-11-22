-- Accounts whose password is managed in the web application.
--
-- The school administration creates teachers there, and the backend
-- gives every world the same password for them. Such an account is
-- marked here. Its password cannot be changed inside the game, neither
-- by the teacher in the client nor by a command: it would count in this
-- world only. The engine asks the authentication handler to store a new
-- password, and takes "no" for an answer.
--
-- Students and accounts the admin made by hand are not marked. They
-- change their passwords in the game as ever.

local load = lep_core.loader("lep_accounts")
local accounts = load("src/accounts")

local S = core.get_translator("lep_accounts")
local PREFIX = "managed:"
local mod_storage = core.get_mod_storage()

--- Returns true if the password of an account is managed in the web
-- application.
function lep_accounts.is_managed(name)
	return type(name) == "string" and mod_storage:get_string(PREFIX .. name) ~= ""
end

function lep_accounts._set_managed(name, managed)
	mod_storage:set_string(PREFIX .. name, managed and "1" or "")
end

-- The handler the engine uses. Another mod that brings its own would
-- have to be loaded before this one; LEP has none.
local handler = core.get_auth_handler()
local store = handler.set_password

--- Stores what the engine keeps of a password, also for a managed
-- account. Only for orders from the backend.
function lep_accounts._write_password(name, entry)
	return store(name, entry)
end

handler.set_password = function(name, password)
	if not accounts.may_change_in_game(lep_accounts.is_managed(name)) then
		core.log("action", "[lep_accounts] " .. tostring(name)
			.. " tried to change a managed password in the game")
		if core.get_player_by_name(name) then
			core.chat_send_player(name, S("The password of this account cannot be changed "
				.. "in the game. The school administration gives you a new one."))
		end
		return false
	end
	return store(name, password)
end

-- The commands of the engine report success whatever the handler says.
for _, command in ipairs({ "setpassword", "clearpassword" }) do
	local definition = core.registered_chatcommands[command]
	if definition then
		local run = definition.func
		core.override_chatcommand(command, { func = function(caller, param)
			local target = param:match("^(%S+)")
			if target and not accounts.may_change_in_game(lep_accounts.is_managed(target)) then
				return false, S("The password of @1 is managed in the web application. "
					.. "The school administration gives out a new one there.", target)
			end
			return run(caller, param)
		end })
	end
end
