-- Shows the display name where the engine itself shows a name: above
-- the figure and in the messages about joining and leaving. Chat, signs
-- and the desk ask lep_accounts.get_display_name on their own.

local function update_nametag(player)
	local account = player:get_player_name()
	local display = lep_accounts.get_display_name(account)
	-- An empty text makes the engine show the account name.
	player:set_nametag_attributes({ text = display ~= account and display or "" })
end

core.register_on_joinplayer(update_nametag)

lep_accounts.register_on_display_name_changed(function(account)
	local player = core.get_player_by_name(account)
	if player then
		update_nametag(player)
	end
end)

-- The engine builds these two messages from the name it is given.
local send_join_message = core.send_join_message
function core.send_join_message(player_name)
	return send_join_message(lep_accounts.get_display_name(player_name))
end

local send_leave_message = core.send_leave_message
function core.send_leave_message(player_name, timed_out)
	return send_leave_message(lep_accounts.get_display_name(player_name), timed_out)
end
