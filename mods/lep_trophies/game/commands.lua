-- Chat commands of lep_trophies.

local S = core.get_translator("lep_trophies")

core.register_chatcommand("lep_trophies", {
	description = S("Show your trophies and how far the next ones are"),
	func = function(name)
		local lines = {}
		local earned = lep_trophies.get_earned(name)
		if #earned == 0 then
			lines[1] = S("You have not earned any trophies yet.")
		else
			lines[1] = S("Your trophies:")
			for _, id in ipairs(earned) do
				lines[#lines + 1] = "  " .. lep_trophies.get_trophy(id).title
			end
		end
		local open = lep_trophies._open_counters(name)
		if #open > 0 then
			lines[#lines + 1] = S("Next:")
			for _, entry in ipairs(open) do
				lines[#lines + 1] = "  " .. S("@1: @2 of @3", entry.title, entry.count,
					entry.target)
			end
		end
		return true, table.concat(lines, "\n")
	end,
})
