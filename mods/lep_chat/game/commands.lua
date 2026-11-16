-- Chat commands of lep_chat.

local S = core.get_translator("lep_chat")

core.register_privilege("lep_view_chat", {
	description = "Can view the protocol of chat and sign texts",
	give_to_singleplayer = false,
	give_to_admin = true,
})

local KINDS = {
	[lep_chat.KIND_CHAT] = "",
	[lep_chat.KIND_ACTION] = " *",
}

-- "2026-11-16T10:00:00Z  anna: hello" for one entry.
local function chat_line(entry)
	if entry.kind == lep_chat.KIND_PRIVATE then
		return entry.time .. "  " .. entry.account .. " -> " .. entry.recipient .. ": "
			.. entry.text
	end
	return entry.time .. "  " .. entry.account .. (KINDS[entry.kind] or "") .. ": " .. entry.text
end

local function sign_line(entry)
	return entry.time .. "  " .. entry.account .. " " .. entry.pos .. ": "
		.. entry.text:gsub("\n", " / ")
end

core.register_chatcommand("lep_chat_log", {
	params = "[signs] [<player>] [<count>]",
	description = S("Show the last chat messages or sign texts, of all or of one player"),
	privs = { lep_view_chat = true },
	func = function(_, param)
		local words = {}
		for word in param:gmatch("%S+") do
			words[#words + 1] = word
		end
		local signs = words[1] == "signs"
		if signs then
			table.remove(words, 1)
		end
		local target, count = nil, 10
		for _, word in ipairs(words) do
			if tonumber(word) then
				count = tonumber(word)
			else
				target = word
			end
		end
		count = math.max(1, math.min(50, math.floor(count)))
		if target and not core.player_exists(target) then
			return false, S("There is no player @1.", target)
		end

		local entries = signs and lep_chat.get_sign_log(target, count)
			or lep_chat.get_log(target, count)
		if #entries == 0 then
			return true, S("Nothing is recorded.")
		end
		local lines = { signs and S("Last sign texts (times in UTC):")
			or S("Last chat messages (times in UTC):") }
		for _, entry in ipairs(entries) do
			lines[#lines + 1] = signs and sign_line(entry) or chat_line(entry)
		end
		return true, table.concat(lines, "\n")
	end,
})
