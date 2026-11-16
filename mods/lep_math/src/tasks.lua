-- The task types of mental arithmetic and their levels. Pure Lua, no
-- engine calls.
--
-- A task type is a rule that makes up a task. A task is a table with
--   text    what the display shows, for example "7+5". The characters are
--           digits and + - * / and the decimal comma.
--   answer  the expected number
-- Random numbers come from a function random(min, max) that is passed in,
-- so the tests can check every rule.

local tasks = {}

-- How often a task type has to be solved, unless it says otherwise.
tasks.REQUIRED = 10

local function task(a, operator, b, answer)
	return { text = a .. operator .. b, answer = answer }
end

-- Picks one entry of a list.
local function pick(random, list)
	return list[random(1, #list)]
end

-- a + b with two one-digit summands and a sum in [min, max].
local function add_small(min, max)
	return function(random)
		local sum = random(min, max)
		local a = random(math.max(1, sum - 9), math.min(9, sum - 1))
		return task(a, "+", sum - a, sum)
	end
end

-- Addition below `limit`, with or without carrying in the ones.
local function add_two_digit(limit, carry, first_min)
	return function(random)
		while true do
			local a = random(first_min, limit - 2)
			local b = random(1, limit - a)
			local ones = a % 10 + b % 10
			if (carry and ones >= 10) or (not carry and ones <= 9 and b % 10 ~= 0) then
				return task(a, "+", b, a + b)
			end
		end
	end
end

-- Subtraction below `limit`, with or without borrowing in the ones.
local function sub_two_digit(limit, borrow, first_min)
	return function(random)
		while true do
			local a = random(first_min, limit)
			local b = random(1, a - 1)
			local needs_borrow = a % 10 < b % 10
			if (borrow and needs_borrow) or (not borrow and not needs_borrow and b % 10 ~= 0) then
				return task(a, "-", b, a - b)
			end
		end
	end
end

-- Times tables of the given rows.
local function multiply(rows)
	return function(random)
		local a, b = pick(random, rows), random(1, 10)
		if random(1, 2) == 1 then
			a, b = b, a
		end
		return task(a, "*", b, a * b)
	end
end

local function divide(rows)
	return function(random)
		local divisor, result = pick(random, rows), random(1, 10)
		return task(divisor * result, "/", divisor, result)
	end
end

-- One decimal place, written with a comma.
local function decimal(tenths)
	local text = string.format("%d,%d", math.floor(tenths / 10), tenths % 10)
	return text
end

-- The levels, in order. Every task type has an id that is unique in the
-- module, a title (translated by the game layer) and its rule.
tasks.LEVELS = {
	{ tasks = {
		{ id = "add_10", title = "Addition up to 10", generate = add_small(2, 10) },
		{ id = "sub_10", title = "Subtraction up to 10", generate = function(random)
			local a = random(2, 10)
			local b = random(1, a - 1)
			return task(a, "-", b, a - b)
		end },
	} },
	{ tasks = {
		{ id = "add_20_plain", title = "Addition up to 20 without carrying",
			generate = add_two_digit(20, false, 10) },
		{ id = "sub_20_plain", title = "Subtraction up to 20 without borrowing",
			generate = sub_two_digit(19, false, 11) },
	} },
	{ stage = true, tasks = {
		{ id = "add_20_carry", title = "Addition up to 20 with carrying",
			generate = add_small(11, 18) },
		{ id = "sub_20_carry", title = "Subtraction up to 20 with borrowing",
			generate = function(random)
				local a = random(11, 18)
				local b = random(a - 9, 9)
				return task(a, "-", b, a - b)
			end },
	} },
	{ tasks = {
		{ id = "add_100_plain", title = "Addition up to 100 without carrying",
			generate = add_two_digit(100, false, 11) },
		{ id = "sub_100_plain", title = "Subtraction up to 100 without borrowing",
			generate = sub_two_digit(99, false, 21) },
	} },
	{ tasks = {
		{ id = "add_100_carry", title = "Addition up to 100 with carrying",
			generate = add_two_digit(100, true, 11) },
		{ id = "sub_100_carry", title = "Subtraction up to 100 with borrowing",
			generate = sub_two_digit(99, true, 21) },
	} },
	{ stage = true, tasks = {
		{ id = "mul_2_5_10", title = "Times tables of 2, 5 and 10", generate = multiply({ 2, 5, 10 }) },
		{ id = "div_2_5_10", title = "Dividing by 2, 5 and 10", generate = divide({ 2, 5, 10 }) },
	} },
	{ tasks = {
		{ id = "mul_3_4_6", title = "Times tables of 3, 4 and 6", generate = multiply({ 3, 4, 6 }) },
		{ id = "div_3_4_6", title = "Dividing by 3, 4 and 6", generate = divide({ 3, 4, 6 }) },
	} },
	{ tasks = {
		{ id = "mul_7_8_9", title = "Times tables of 7, 8 and 9", generate = multiply({ 7, 8, 9 }) },
		{ id = "div_7_8_9", title = "Dividing by 7, 8 and 9", generate = divide({ 7, 8, 9 }) },
	} },
	{ stage = true, tasks = {
		{ id = "mixed", title = "Mixed tasks: multiply before adding", required = 5,
			generate = function(random)
				local a, b, c = random(2, 9), random(2, 9), random(1, 20)
				local kind = random(1, 3)
				if kind == 1 then
					return { text = c .. "+" .. a .. "*" .. b, answer = c + a * b }
				elseif kind == 2 then
					return { text = a .. "*" .. b .. "+" .. c, answer = a * b + c }
				end
				c = random(1, a * b)
				return { text = a .. "*" .. b .. "-" .. c, answer = a * b - c }
			end },
	} },
	{ tasks = {
		{ id = "add_1000", title = "Addition up to 1000", generate = function(random)
			local a = random(101, 899)
			local b = random(11, 1000 - a)
			return task(a, "+", b, a + b)
		end },
		{ id = "sub_1000", title = "Subtraction up to 1000", generate = function(random)
			local a = random(201, 1000)
			local b = random(11, a - 1)
			return task(a, "-", b, a - b)
		end },
	} },
	{ tasks = {
		{ id = "mul_tens", title = "Multiplying tens", generate = function(random)
			local a, b = random(1, 9) * 10, random(2, 9)
			return task(a, "*", b, a * b)
		end },
		{ id = "div_tens", title = "Dividing to tens", generate = function(random)
			local result, divisor = random(1, 9) * 10, random(2, 9)
			return task(result * divisor, "/", divisor, result)
		end },
	} },
	{ tasks = {
		{ id = "dec_add", title = "Adding decimals", generate = function(random)
			local a, b = random(11, 499), random(11, 499)
			return { text = decimal(a) .. "+" .. decimal(b), answer = (a + b) / 10 }
		end },
		{ id = "dec_sub", title = "Subtracting decimals", generate = function(random)
			local a = random(21, 999)
			local b = random(11, a - 1)
			return { text = decimal(a) .. "-" .. decimal(b), answer = (a - b) / 10 }
		end },
	} },
}

local by_id = {}
for number, level in ipairs(tasks.LEVELS) do
	for _, entry in ipairs(level.tasks) do
		entry.level = number
		entry.required = entry.required or tasks.REQUIRED
		by_id[entry.id] = entry
	end
end

--- Returns the task type with this id, or nil.
function tasks.get(id)
	return by_id[id]
end

--- Makes up a task of a task type.
-- @param random Function(min, max) returning a whole number in that range.
-- @return Table with text, answer and type (the id).
function tasks.generate(id, random)
	local entry = assert(by_id[id], "unknown task type '" .. tostring(id) .. "'")
	local result = entry.generate(random)
	result.type = id
	return result
end

--- Chooses the task type for the next task: one the player has not done
-- yet if there is one, otherwise any of the level.
-- @param progress List of the task types of the level, each with id,
--   solved and required, as lep_progress reports them.
function tasks.choose(progress, random)
	local open = {}
	for _, entry in ipairs(progress) do
		if entry.solved < entry.required then
			open[#open + 1] = entry.id
		end
	end
	if #open > 0 then
		return pick(random, open)
	end
	return progress[random(1, #progress)].id
end

return tasks
