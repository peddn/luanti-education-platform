-- What the three reward sizes contain and how many daily tasks are
-- rewarded per day.
-- Only this file knows where that comes from. For now it is the server
-- configuration, later the backend with a table per group.

local load = lep_core.loader("lep_rewards")
local rewards = load("src/rewards")

local config = {}

local function read_items(size)
	local setting = "lep_rewards_" .. size
	local text = core.settings:get(setting)
	if text and text ~= "" then
		local items, err = rewards.parse_items(text)
		if items then
			return items
		end
		core.log("error", "[lep_rewards] setting " .. setting .. ": " .. err
			.. ". Using the default.")
	end
	return rewards.parse_items(rewards.DEFAULT_ITEMS[size])
end

local function read_daily_limit()
	local value = tonumber(core.settings:get("lep_rewards_daily_limit"))
	if value and value >= 0 then
		return math.floor(value)
	end
	return rewards.DEFAULT_DAILY_LIMIT
end

local items = {}
for _, size in ipairs(rewards.SIZES) do
	items[size] = read_items(size)
end

local daily_limit = read_daily_limit()

-- Items can only be checked once all mods are loaded.
core.register_on_mods_loaded(function()
	for _, size in ipairs(rewards.SIZES) do
		for _, item in ipairs(items[size]) do
			if not core.registered_items[item.name] then
				core.log("error", "[lep_rewards] reward '" .. size
					.. "' contains the unknown item " .. item.name)
			end
		end
	end
end)

--- Returns the items of a size as a list of { name, count }.
function config.items(size)
	return items[size]
end

--- Returns how many daily tasks are rewarded per player and day.
function config.daily_limit()
	return daily_limit
end

return config
