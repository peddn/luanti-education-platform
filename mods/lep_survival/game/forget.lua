-- An account that is removed: what the mods of the survival world keep
-- about it. They are not ours, so this is done here for them.

lep_core.register_on_forget_account(function(account)
	-- The awards mod counts what a player dug, placed and crafted. It can
	-- only empty the entry of a player, not drop it: the account name
	-- stays in its storage, without any data.
	if rawget(_G, "awards") and awards.player_or_nil(account) then
		awards.clear_player(account)
		awards.save()
	end
	-- The bed a player respawns at.
	if rawget(_G, "beds") and type(beds.spawn) == "table" and beds.spawn[account] then
		beds.spawn[account] = nil
		beds.save_spawns()
	end
end)
