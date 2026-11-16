-- How achievements of the third-party mod "awards" become trophies.
-- Pure Lua, no engine calls.

local achievements = {}

-- Achievements that are switched off. Nobody can unlock them.
achievements.DISABLED = {
	-- "Die 100 times", in the original titled "You Suck!".
	award_you_suck = true,
}

--- Returns true if the achievement is switched off.
function achievements.is_disabled(award_name)
	return achievements.DISABLED[award_name] == true
end

--- Returns the id of the trophy for an achievement.
function achievements.trophy_id(award_name)
	return "lep_survival:award:" .. award_name
end

--- Returns the name of the node that shows an achievement on a pedestal.
-- Node names allow only letters, digits and underscores.
function achievements.node_name(award_name)
	return "lep_survival:plaque_" .. (award_name:lower():gsub("[^a-z0-9_]", "_"))
end

--- Returns the names of the achievements that become trophies, sorted.
-- @param registered Table with the achievement names as keys.
function achievements.as_trophies(registered)
	local names = {}
	for award_name in pairs(registered) do
		if not achievements.is_disabled(award_name) then
			names[#names + 1] = award_name
		end
	end
	table.sort(names)
	return names
end

return achievements
