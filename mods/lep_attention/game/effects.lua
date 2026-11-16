-- What a student in the attention mode sees and hears: a black screen
-- with the teacher's text, no chat, no inventory.

local load = lep_core.loader("lep_attention")
local attention = load("src/attention")
local S = core.get_translator("lep_attention")

local effects = {}

-- What is hidden while the screen is black.
local HIDDEN_FLAGS = { "hotbar", "healthbar", "crosshair", "wielditem", "breathbar",
	"minimap", "minimap_radar", "chat" }
-- An inventory window without content: nothing to see, nothing to click.
local EMPTY_INVENTORY = "formspec_version[6]size[0.1,0.1]no_prepend[]bgcolor[#00000000;neither]"

-- Per player while the effects are on: hud (ids), flags (as before).
local applied = {}

local function hud_text(text)
	return text or S(attention.DEFAULT_TEXT)
end

--- Switches the effects on for an online player, or updates the text.
function effects.apply(player_name, text)
	local player = core.get_player_by_name(player_name)
	if not player then
		return
	end
	local state = applied[player_name]
	if state then
		player:hud_change(state.hud.text, "text", hud_text(text))
		return
	end

	-- Windows that are open would lie on top of the black screen.
	core.close_formspec(player_name, "")

	state = { hud = {}, flags = player:hud_get_flags() }
	state.hud.screen = player:hud_add({
		type = "image",
		position = { x = 0.5, y = 0.5 },
		-- Negative scale is a share of the screen in percent.
		scale = { x = -100, y = -100 },
		alignment = { x = 0, y = 0 },
		text = "[fill:16x16:#000000",
		z_index = 1000,
	})
	state.hud.text = player:hud_add({
		type = "text",
		position = { x = 0.5, y = 0.5 },
		alignment = { x = 0, y = 0 },
		size = { x = 2, y = 2 },
		number = 0xFFFFFF,
		text = hud_text(text),
		z_index = 1001,
	})

	local flags = {}
	for _, flag in ipairs(HIDDEN_FLAGS) do
		flags[flag] = false
	end
	player:hud_set_flags(flags)
	player:set_inventory_formspec(EMPTY_INVENTORY)
	lep_chat.set_deaf(player_name, true)
	applied[player_name] = state
end

--- Switches the effects off.
function effects.remove(player_name)
	lep_chat.set_deaf(player_name, false)
	local state = applied[player_name]
	applied[player_name] = nil
	local player = core.get_player_by_name(player_name)
	if not state or not player then
		return
	end
	for _, id in pairs(state.hud) do
		player:hud_remove(id)
	end
	local flags = {}
	for _, flag in ipairs(HIDDEN_FLAGS) do
		if state.flags[flag] ~= nil then
			flags[flag] = state.flags[flag]
		end
	end
	player:hud_set_flags(flags)
	-- Minetest Game builds the inventory window with sfinv.
	if core.global_exists("sfinv") then
		sfinv.set_player_inventory_formspec(player)
	end
end

core.register_on_leaveplayer(function(player)
	-- HUD and flags are gone with the session. The player stays deaf: a
	-- student in the mode who joins again is deaf from the first moment.
	applied[player:get_player_name()] = nil
end)

return effects
