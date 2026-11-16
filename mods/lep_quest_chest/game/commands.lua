-- Chat commands of lep_quest_chest.

local S = core.get_translator("lep_quest_chest")

core.register_chatcommand("lep_quest_chest", {
	description = S("Get a task chest to place. It stays until it is removed"),
	privs = { [lep_quest_chest.PRIVILEGE] = true },
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, S("You have to be in the game.")
		end
		local leftover = player:get_inventory():add_item("main",
			ItemStack(lep_quest_chest.NODE))
		if not leftover:is_empty() then
			return false, S("Your inventory is full.")
		end
		return true, S("You got a task chest. Place it like a block. "
			.. "Remove it with the button in its window.")
	end,
})
