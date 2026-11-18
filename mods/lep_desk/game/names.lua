-- Tells everybody who may open the desk when a player chooses a display
-- name. Nobody approves names, so the teachers in the game hear of each
-- one. This message is the one place in the game that names both the
-- account and the new name.

local S = core.get_translator("lep_desk")

if not core.global_exists("lep_accounts") then
	return
end

lep_accounts.register_on_display_name_changed(function(account, action)
	local message
	if action == lep_accounts.NAME_CHOSEN then
		message = S("@1 is now called @2.", account, lep_accounts.get_display_name(account))
	elseif action == lep_accounts.NAME_GIVEN_UP then
		message = S("@1 goes by the account name again.", account)
	else
		-- What a teacher did needs no message to the teachers.
		return
	end
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if lep_desk.may_open(name) then
			core.chat_send_player(name, message)
		end
	end
end)
