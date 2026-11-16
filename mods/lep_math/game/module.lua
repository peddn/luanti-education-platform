-- Registers mental arithmetic as a learning module.

local load = lep_core.loader("lep_math")
local tasks = load("src/tasks")
local S = core.get_translator("lep_math")

lep_math.MODULE = "lep_math:math"

local levels = {}
for number, level in ipairs(tasks.LEVELS) do
	local list = {}
	for index, entry in ipairs(level.tasks) do
		-- The titles are written in English in src/tasks.lua and
		-- translated here.
		list[index] = { id = entry.id, title = S(entry.title), required = entry.required }
	end
	levels[number] = { stage = level.stage, tasks = list }
end

lep_progress.register_module(lep_math.MODULE, {
	title = S("Mental arithmetic"),
	levels = levels,
})
