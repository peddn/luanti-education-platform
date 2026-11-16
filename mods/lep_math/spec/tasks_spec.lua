local tasks = dofile("mods/lep_math/src/tasks.lua")
local layout = dofile("mods/lep_math/src/layout.lua")

-- A simple repeatable random number generator. Only the upper bits are
-- used: the lower bits of this kind of generator repeat quickly.
local function new_random(seed)
	local state = seed
	return function(min, max)
		state = (state * 1103515245 + 12345) % 2147483648
		return min + math.floor(state / 65536) % (max - min + 1)
	end
end

local function evaluate(text)
	local expression = text:gsub(",", ".")
	return assert(loadstring("return " .. expression))()
end

-- Splits "a+b" or "a-b" into its numbers.
local function operands(text)
	local a, operator, b = text:match("^(%d+)([%+%-%*/])(%d+)$")
	return tonumber(a), operator, tonumber(b)
end

local function samples(id, count)
	local random = new_random(#id * 7919 + 1)
	local list = {}
	for index = 1, count or 400 do
		list[index] = tasks.generate(id, random)
	end
	return list
end

describe("lep_math task types", function()
	it("has twelve levels with stages at 3, 6, 9 and unique ids", function()
		assert.are.equal(12, #tasks.LEVELS)
		local seen = {}
		for number, level in ipairs(tasks.LEVELS) do
			assert.are.equal(number == 3 or number == 6 or number == 9, level.stage == true)
			assert.is_true(#level.tasks >= 1)
			for _, entry in ipairs(level.tasks) do
				assert.is_nil(seen[entry.id])
				seen[entry.id] = true
				assert.are.equal(number, tasks.get(entry.id).level)
				assert.is_truthy(entry.title)
			end
		end
		assert.are.equal(5, tasks.get("mixed").required)
		assert.are.equal(10, tasks.get("add_10").required)
		assert.is_nil(tasks.get("nope"))
	end)

	for number, level in ipairs(tasks.LEVELS) do
		for _, entry in ipairs(level.tasks) do
			it("makes correct tasks that fit the display: " .. entry.id, function()
				local different = {}
				for _, task in ipairs(samples(entry.id)) do
					assert.are.equal(entry.id, task.type)
					assert.is_truthy(task.text:match("^[%d%+%-%*/,]+$"), task.text)
					assert.is_true(#task.text <= layout.COLUMNS, task.text)
					assert.is_true(math.abs(evaluate(task.text) - task.answer) < 0.0001, task.text)
					assert.is_true(task.answer >= 0, task.text)
					if number < 12 then
						assert.are.equal(math.floor(task.answer), task.answer, task.text)
					end
					different[task.text] = true
				end
				local count = 0
				for _ in pairs(different) do
					count = count + 1
				end
				assert.is_true(count >= 8, "too few different tasks: " .. count)
			end)
		end
	end

	it("keeps levels 1 to 3 within their number range", function()
		for _, task in ipairs(samples("add_10")) do
			local a, _, b = operands(task.text)
			assert.is_true(a >= 1 and b >= 1 and a + b <= 10, task.text)
		end
		for _, task in ipairs(samples("sub_10")) do
			local a, _, b = operands(task.text)
			assert.is_true(a <= 10 and b >= 1 and b < a, task.text)
		end
		for _, task in ipairs(samples("add_20_plain")) do
			local a, _, b = operands(task.text)
			assert.is_true(a + b <= 20 and a % 10 + b % 10 <= 9, task.text)
		end
		for _, task in ipairs(samples("sub_20_plain")) do
			local a, _, b = operands(task.text)
			assert.is_true(a <= 20 and a % 10 >= b % 10, task.text)
		end
		for _, task in ipairs(samples("add_20_carry")) do
			local a, _, b = operands(task.text)
			assert.is_true(a <= 9 and b <= 9 and a + b > 10 and a + b <= 20, task.text)
		end
		for _, task in ipairs(samples("sub_20_carry")) do
			local a, _, b = operands(task.text)
			assert.is_true(a <= 20 and b <= 9 and a % 10 < b, task.text)
		end
	end)

	it("carries and borrows exactly where the task type says so", function()
		for _, task in ipairs(samples("add_100_plain")) do
			local a, _, b = operands(task.text)
			assert.is_true(a + b <= 100 and a % 10 + b % 10 <= 9, task.text)
		end
		for _, task in ipairs(samples("add_100_carry")) do
			local a, _, b = operands(task.text)
			assert.is_true(a + b <= 100 and a % 10 + b % 10 >= 10, task.text)
		end
		for _, task in ipairs(samples("sub_100_plain")) do
			local a, _, b = operands(task.text)
			assert.is_true(a <= 100 and a % 10 >= b % 10, task.text)
		end
		for _, task in ipairs(samples("sub_100_carry")) do
			local a, _, b = operands(task.text)
			assert.is_true(a <= 100 and a % 10 < b % 10, task.text)
		end
		for _, task in ipairs(samples("add_1000")) do
			assert.is_true(task.answer <= 1000, task.text)
		end
	end)

	it("uses only the stated rows in times tables and divides without remainder", function()
		local rows = {
			mul_2_5_10 = { [2] = true, [5] = true, [10] = true },
			mul_3_4_6 = { [3] = true, [4] = true, [6] = true },
			mul_7_8_9 = { [7] = true, [8] = true, [9] = true },
		}
		for id, allowed in pairs(rows) do
			for _, task in ipairs(samples(id)) do
				local a, _, b = operands(task.text)
				assert.is_true((allowed[a] and b <= 10) or (allowed[b] and a <= 10), task.text)
			end
		end
		for _, id in ipairs({ "div_2_5_10", "div_3_4_6", "div_7_8_9", "div_tens" }) do
			for _, task in ipairs(samples(id)) do
				local a, _, b = operands(task.text)
				assert.are.equal(0, a % b, task.text)
				assert.is_true(b >= 2, task.text)
			end
		end
	end)

	it("writes decimals with a comma and one decimal place", function()
		for _, id in ipairs({ "dec_add", "dec_sub" }) do
			for _, task in ipairs(samples(id)) do
				assert.is_truthy(task.text:match("^%d+,%d[%+%-]%d+,%d$"), task.text)
			end
		end
	end)

	it("fails for an unknown task type", function()
		assert.has_error(function() tasks.generate("nope", new_random(1)) end)
	end)
end)

describe("lep_math choosing the next task type", function()
	it("prefers task types that are not done", function()
		local progress = {
			{ id = "a", solved = 10, required = 10 },
			{ id = "b", solved = 3, required = 10 },
		}
		local random = new_random(5)
		for _ = 1, 50 do
			assert.are.equal("b", tasks.choose(progress, random))
		end
	end)

	it("takes any task type when all are done", function()
		local progress = {
			{ id = "a", solved = 10, required = 10 },
			{ id = "b", solved = 10, required = 10 },
		}
		local random = new_random(5)
		local seen = {}
		for _ = 1, 50 do
			seen[tasks.choose(progress, random)] = true
		end
		assert.is_true(seen.a and seen.b)
	end)
end)
