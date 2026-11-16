local reports = dofile("mods/lep_bridge/src/reports.lua")
local schema = dofile("mods/lep_bridge/spec/schema.lua")

local fits = schema.load("api/openapi.json")

describe("lep_bridge reports", function()
	it("builds the list of modules as the backend expects it", function()
		local payload = reports.modules({
			{ id = "lep_math:math", title = "Kopfrechnen", levels = {
				{ stage = false, tasks = { { id = "add_10", title = "Addition bis 10",
					required = 10 } } },
				{ stage = true, tasks = {} },
			} },
		})
		assert.is_true(fits("Modules", payload))
		assert.are.equal("Kopfrechnen", payload.modules[1].title)
		assert.is_false(payload.modules[1].levels[1].stage)
		assert.are.equal(10, payload.modules[1].levels[1].tasks[1].required)
		assert.is_true(fits("Modules", reports.modules({})))
	end)

	it("builds the progress of a student as the backend expects it", function()
		local payload = reports.progress("anna", {
			module_id = "lep_math:math", title = "Kopfrechnen", level = 3, levels = 12,
			percent = 45.5, locked = false, level_completed = false, completed = false,
			tasks = {
				{ id = "add_20_carry", title = "x", solved = 9, required = 10 },
				{ id = "sub_20_carry", title = "y", solved = 0, required = 10 },
			},
		})
		assert.is_true(fits("Progress", payload))
		assert.are.equal("anna", payload.account)
		assert.are.equal("lep_math:math", payload.module)
		assert.are.equal(45, payload.percent)
		assert.are.same({ id = "add_20_carry", solved = 9, required = 10 }, payload.tasks[1])
		-- Titles of tasks belong to the module, not to the state.
		assert.is_nil(payload.tasks[1].title)
	end)

	it("keeps the numbers of progress in their range", function()
		local payload = reports.progress("anna", {
			module_id = "m", level = 2.9, percent = 180, locked = nil, completed = nil,
			tasks = { { id = "t", solved = -3, required = "5" } },
		})
		assert.is_true(fits("Progress", payload))
		assert.are.equal(2, payload.level)
		assert.are.equal(100, payload.percent)
		assert.is_false(payload.locked)
		assert.are.same({ id = "t", solved = 0, required = 5 }, payload.tasks[1])
	end)

	it("builds the trophies of a student as the backend expects them", function()
		local payload = reports.trophies("anna", {
			{ id = "lep_trophies:tasks_10", title = "10 Aufgaben", material = "bronze" },
		})
		assert.is_true(fits("Trophies", payload))
		assert.is_true(fits("Trophies", reports.trophies("anna", {})))
	end)

	it("turns a protocol entry into account and fields", function()
		local payload = reports.protocol("rewards", {
			account = "anna", size = "medium", reason = "daily", module = "lep_math:math",
			level = 3, task = "", items = "default:gold_ingot 1",
		})
		assert.is_true(fits("ProtocolEntry", payload))
		assert.are.equal("rewards", payload.protocol)
		assert.are.equal("anna", payload.account)
		assert.are.same({ size = "medium", reason = "daily", module = "lep_math:math",
			level = "3", items = "default:gold_ingot 1" }, payload.fields)
	end)

	it("reports no protocol entry without an account", function()
		assert.is_nil(reports.protocol("chat", { text = "hello" }))
		assert.is_nil(reports.protocol("chat", { account = "", text = "hello" }))
		local bare = reports.protocol("desk", { account = "teacher" })
		assert.is_true(fits("ProtocolEntry", bare))
		assert.are.same({}, bare.fields)
	end)

	it("names events and jobs as the backend does", function()
		local json = require("dkjson")
		local file = assert(io.open("api/openapi.json"))
		local schemas = json.decode(file:read("*a")).components.schemas
		file:close()
		for _, name in ipairs({ "Modules", "Progress", "Trophies", "ProtocolEntry" }) do
			assert.is_not_nil(schemas[name], name)
		end
		assert.are.equal("progress", reports.EVENT_PROGRESS)
		assert.are.equal("sync_state", reports.JOB_SYNC_STATE)
	end)

	it("builds the list of teachers as the backend expects it", function()
		local payload = reports.teachers({ "lehrer1", "lehrer2" })
		assert.is_true(fits("Teachers", payload))
		assert.are.same({ accounts = { "lehrer1", "lehrer2" } }, payload)
		assert.is_true(fits("Teachers", reports.teachers({})))
	end)

	it("builds requests about web access as the backend expects them", function()
		local set = reports.web_access("lehrer1", "set", "anna@schule.example")
		assert.is_true(fits("WebAccessRequest", set))
		assert.are.same({ account = "lehrer1", action = "set",
			email = "anna@schule.example" }, set)

		-- Only "set" carries an address.
		local resend = reports.web_access("lehrer1", "resend", "anna@schule.example")
		assert.is_true(fits("WebAccessRequest", resend))
		assert.are.same({ account = "lehrer1", action = "resend" }, resend)
		assert.is_true(fits("WebAccessRequest", reports.web_access("lehrer1", "remove")))

		assert.has_error(function() reports.web_access("lehrer1", "explode") end)
		assert.has_error(function() reports.web_access("lehrer1", "set") end)
		assert.has_error(function() reports.web_access("", "remove") end)
	end)

	it("reads how a web access stands", function()
		local status = { account = "lehrer1", address = "a…@schule.example" }
		assert.is_true(fits("WebAccessStatus", status))
		local account, address, pending = reports.parse_web_access_status(status)
		assert.are.equal("lehrer1", account)
		assert.are.equal("a…@schule.example", address)
		assert.is_nil(pending)

		account, address, pending = reports.parse_web_access_status(
			{ account = "lehrer1", pending = "n…@schule.example" })
		assert.are.equal("lehrer1", account)
		assert.is_nil(address)
		assert.are.equal("n…@schule.example", pending)

		assert.is_nil(reports.parse_web_access_status(nil))
		assert.is_nil(reports.parse_web_access_status({ address = "x" }))
		assert.is_nil(reports.parse_web_access_status({ account = "" }))
	end)
end)
