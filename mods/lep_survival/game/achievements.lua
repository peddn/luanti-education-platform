-- Turns achievements of the third-party mod "awards" into trophies.
--
-- The awards mod counts what players do in survival and unlocks
-- achievements. This file only listens: an unlocked achievement becomes a
-- trophy that belongs to the account. The counters stay with awards.

local load = lep_core.loader("lep_survival")
local achievements = load("src/achievements")

-- Some achievements are not wanted. Their definition asks awards whether
-- they can be unlocked: say no. They are secret, so they stay hidden too.
for award_name in pairs(achievements.DISABLED) do
	local def = awards.registered_awards[award_name]
	if def then
		def.can_unlock = function()
			return false
		end
		def.secret = true
	end
end

-- A plaque with the icon of the achievement, shown on a pedestal.
local function register_plaque(award_name, def)
	local icon = def.icon or "awards_unknown.png"
	core.register_node(achievements.node_name(award_name), {
		description = "LEP achievement plaque",
		drawtype = "nodebox",
		-- A face of a node box shows only the part of the texture that the
		-- box covers. The plaque is as large as a node, so the whole icon
		-- is visible.
		node_box = { type = "fixed", fixed = { -0.5, -0.5, -0.05, 0.5, 0.5, 0.05 } },
		tiles = {
			"default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png",
			icon, icon,
		},
		use_texture_alpha = "clip",
		paramtype = "light",
		paramtype2 = "facedir",
		sunlight_propagates = true,
		groups = { not_in_creative_inventory = 1 },
		sounds = default and default.node_sound_wood_defaults() or nil,
		diggable = false,
		is_ground_content = false,
		drop = "",
		on_blast = function() end,
		can_dig = function() return false end,
	})
end

-- Nodes can only be registered while the mods load: plaques for the
-- achievements known now. Later ones are shown as a cup.
for _, award_name in ipairs(achievements.as_trophies(awards.registered_awards)) do
	register_plaque(award_name, awards.registered_awards[award_name])
end

-- Makes sure the trophy for an achievement exists.
-- @return the trophy id, or nil for a disabled or unknown achievement
local function ensure_trophy(award_name)
	local def = awards.registered_awards[award_name]
	if not def or achievements.is_disabled(award_name) then
		return nil
	end
	local id = achievements.trophy_id(award_name)
	if not lep_trophies.get_trophy(id) then
		local node = achievements.node_name(award_name)
		lep_trophies.register_trophy(id, {
			title = def.title or award_name,
			description = def.description,
			node = core.registered_nodes[node] and node or nil,
		})
	end
	return id
end

-- Trophies for all achievements. The awards mod registers a few of its
-- own only after the server has started, so look again a moment later.
local function ensure_all()
	for _, award_name in ipairs(achievements.as_trophies(awards.registered_awards)) do
		ensure_trophy(award_name)
	end
end

core.register_on_mods_loaded(function()
	ensure_all()
	core.after(1, ensure_all)
end)

local function to_trophy(player_name, award_name)
	local id = ensure_trophy(award_name)
	if id then
		lep_trophies.award(player_name, id)
	end
end

-- Returning nothing lets awards show its own notification as usual.
awards.register_on_unlock(function(player_name, def)
	to_trophy(player_name, def.name)
end)

-- Achievements unlocked before this bridge existed.
core.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	local data = awards.player_or_nil(player_name)
	if data and type(data.unlocked) == "table" then
		for award_name in pairs(data.unlocked) do
			to_trophy(player_name, award_name)
		end
	end
end)
