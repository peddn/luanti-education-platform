-- Debug helpers. Only loaded when the setting "lep_debug" is true.
-- Teachers take names away and lock choosing in the web application;
-- these commands do the same while trying things out.

if not core.registered_privileges.lep_debug then
	core.register_privilege("lep_debug", {
		description = "Can use LEP debug commands",
		give_to_singleplayer = false,
	})
end

local function known(account)
	if account == "" or not lep_accounts.exists(account) then
		return false, "No such account: " .. account
	end
	return true
end

core.register_chatcommand("lep_name_remove", {
	params = "<account>",
	description = "Debug: take the display name of an account away",
	privs = { lep_debug = true },
	func = function(player_name, param)
		local account = param:match("^%s*(%S*)")
		local ok, err = known(account)
		if not ok then
			return false, err
		end
		if lep_accounts.remove_display_name(account, player_name) then
			return true, "Display name of " .. account .. " removed."
		end
		return true, account .. " has no display name."
	end,
})

core.register_chatcommand("lep_name_lock", {
	params = "<account> on|off",
	description = "Debug: lock or unlock choosing a display name for an account",
	privs = { lep_debug = true },
	func = function(player_name, param)
		local account, switch = param:match("^%s*(%S+)%s+(%S+)%s*$")
		if switch ~= "on" and switch ~= "off" then
			return false, "Usage: /lep_name_lock <account> on|off"
		end
		local ok, err = known(account)
		if not ok then
			return false, err
		end
		lep_accounts.set_display_locked(account, switch == "on", player_name)
		return true, "Choosing a display name is " .. (switch == "on" and "locked" or "unlocked")
			.. " for " .. account .. "."
	end,
})

core.register_chatcommand("lep_name_wait", {
	params = "<account>",
	description = "Debug: end the wait of an account for its next display name",
	privs = { lep_debug = true },
	func = function(_, param)
		local account = param:match("^%s*(%S*)")
		local ok, err = known(account)
		if not ok then
			return false, err
		end
		lep_accounts._reset_display_wait(account)
		return true, account .. " can choose a display name again."
	end,
})
