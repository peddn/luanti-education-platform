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

	it("reports the display name of an account as a whole state", function()
		local payload = reports.display_name("klugeEule",
			{ display = "Jörg Weiß", changed_at = 1700000000.7, locked = false, next_change = 5 })
		assert.is_true(fits("DisplayName", payload))
		assert.are.same({ account = "klugeEule", name = "Jörg Weiß", changed_at = 1700000000,
			locked = false }, payload)
		-- No name, only a lock.
		local bare = reports.display_name("klugeEule", { locked = true })
		assert.is_true(fits("DisplayName", bare))
		assert.are.same({ account = "klugeEule", locked = true }, bare)
		assert.are.equal("display_name", reports.EVENT_DISPLAY_NAME)
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
		local payload = reports.teachers({ "lehrer1", "lehrer2" }, { "lehrer2" })
		assert.is_true(fits("Teachers", payload))
		assert.are.same({ accounts = { "lehrer1", "lehrer2" },
			school_admins = { "lehrer2" } }, payload)
		assert.is_true(fits("Teachers", reports.teachers({}, {})))
		assert.are.same({ accounts = { "lehrer1" }, school_admins = {} },
			reports.teachers({ "lehrer1" }))
	end)

	it("reports the passwords of teachers with their version", function()
		local entry, other = "#1#c2FsdDE#dmVyaWZpZXIx", "#1#c2FsdDI#dmVyaWZpZXIy"
		local function mark_of(text)
			return "mark-of-" .. #text .. text:sub(-1)
		end
		local records = {
			-- Written on order of the backend and untouched since.
			lehrer1 = reports.staff_password_record(3, mark_of(entry)),
			-- Changed in this world since.
			lehrer2 = reports.staff_password_record(3, mark_of(entry)),
		}
		local function record_of(name)
			return reports.parse_staff_password_record(records[name])
		end
		local function may_leave(text)
			return text:sub(1, 3) == "#1#"
		end
		records.lehrer4 = reports.staff_password_record(2, mark_of("legacy"))
		local payload = reports.staff_passwords({
			{ name = "lehrer1", entry = entry },
			{ name = "lehrer2", entry = other },
			-- Made in the game: the backend never wrote anything.
			{ name = "lehrer3", entry = other },
			-- Set by a command in the world: what is stored stays there.
			{ name = "lehrer4", entry = "legacy" },
		}, record_of, mark_of, may_leave)
		assert.is_true(fits("StaffPasswords", payload))
		assert.are.same({ accounts = {
			{ name = "lehrer1", entry = entry, version = 3, changed = false },
			{ name = "lehrer2", entry = other, version = 3, changed = true },
			{ name = "lehrer3", entry = other, version = 0, changed = true },
			{ name = "lehrer4", version = 2, changed = false },
		} }, payload)
		assert.is_true(fits("StaffPasswords",
			reports.staff_passwords({}, record_of, mark_of, may_leave)))
		assert.are.equal("staff_passwords", reports.EVENT_STAFF_PASSWORDS)
		assert.are.equal("set_password_entry", reports.JOB_SET_PASSWORD_ENTRY)

		-- The mark tells every change apart: entry, version and whether
		-- it was changed here.
		local mark = reports.staff_passwords_mark(payload)
		assert.are.equal(mark, reports.staff_passwords_mark(payload))
		for _, change in ipairs({ { "entry", entry }, { "version", 4 }, { "changed", false } }) do
			local copy = reports.staff_passwords({ { name = "lehrer1", entry = entry },
				{ name = "lehrer2", entry = other }, { name = "lehrer3", entry = other } },
				record_of, mark_of, may_leave)
			copy.accounts[2][change[1]] = change[2]
			assert.are_not.equal(mark, reports.staff_passwords_mark(copy), change[1])
		end
		assert.are_not.equal(mark, reports.staff_passwords_mark({ accounts = {} }))

		assert.are.same({ 3, "abc" }, { reports.parse_staff_password_record("3 abc") })
		assert.is_nil(reports.parse_staff_password_record(""))
		assert.is_nil(reports.parse_staff_password_record(nil))
		assert.is_nil(reports.parse_staff_password_record("abc"))
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

	it("reports created accounts as the backend expects it", function()
		local payload = reports.accounts_created({ "klugeEule" }, { "frohesReh" })
		assert.is_true(fits("AccountsCreated", payload))
		assert.are.same({ created = { "klugeEule" }, refused = { "frohesReh" } }, payload)
		assert.is_true(fits("AccountsCreated", reports.accounts_created({}, {})))

		-- What the backend orders is what the core reads.
		local accounts = dofile("mods/lep_bridge/src/accounts.lua")
		local order = { accounts = { { name = "klugeEule", password = "wolke-apfel-47" } } }
		assert.is_true(fits("CreateAccounts", order))
		assert.are.same(order.accounts, accounts.parse(order))

		local reset = { name = "klugeEule", password = "berg-see-03" }
		assert.is_true(fits("SetPassword", reset))
		assert.are.equal("klugeEule", (accounts.parse_password(reset)))
	end)

	it("reports that an account was used, and that one was removed", function()
		assert.is_true(fits("AccountUsed", reports.account_used("klugeEule")))
		local payload = reports.account_removed("klugeEule", "leitung")
		assert.is_true(fits("AccountRemoved", payload))
		assert.are.same({ account = "klugeEule", by = "leitung" }, payload)
		-- Removed in the world itself: nobody ordered it from outside.
		assert.is_true(fits("AccountRemoved", reports.account_removed("klugeEule")))
		assert.are.same({ account = "klugeEule" }, reports.account_removed("klugeEule", ""))
		assert.are.equal("account_used", reports.EVENT_ACCOUNT_USED)
		assert.are.equal("account_removed", reports.EVENT_ACCOUNT_REMOVED)
		assert.are.equal("remove_account", reports.JOB_REMOVE_ACCOUNT)
	end)

	it("knows which waiting events are about an account", function()
		local function event(kind, payload)
			return { id = "x", kind = kind, time = 1, payload = payload }
		end
		assert.is_true(reports.concerns(event("progress", { account = "anna" }), "anna"))
		assert.is_true(reports.concerns(event("display_name", { account = "anna" }), "anna"))
		assert.is_true(reports.concerns(event("protocol",
			{ protocol = "chat", account = "anna", fields = { text = "hi" } }), "anna"))
		-- A private message to the account.
		assert.is_true(reports.concerns(event("protocol",
			{ protocol = "chat", account = "ben", fields = { recipient = "anna" } }), "anna"))
		-- Others, and lines that only mention the account.
		assert.is_false(reports.concerns(event("progress", { account = "ben" }), "anna"))
		assert.is_false(reports.concerns(event("protocol",
			{ protocol = "desk", account = "lehrer1", fields = { targets = "anna" } }), "anna"))
		assert.is_false(reports.concerns(event("teachers", { accounts = { "anna" } }), "anna"))
		-- The news of the removal itself has to arrive.
		assert.is_false(reports.concerns(event("account_removed", { account = "anna" }), "anna"))
		assert.is_false(reports.concerns(event("modules", nil), "anna"))
	end)
	it("reports the start level with each module, 1 where none is set", function()
		local payload = reports.modules({
			{ id = "lep_math:math", title = "Kopfrechnen", levels = {}, start_level = 3 },
			{ id = "lep_debug:test", title = "Testmodul", levels = {} },
		})
		assert.is_true(fits("Modules", payload))
		assert.are.equal(3, payload.modules[1].start_level)
		assert.are.equal(1, payload.modules[2].start_level)
		assert.are.equal("set_start_level", reports.JOB_SET_START_LEVEL)
	end)
	it("reports the reward table and the items to choose from", function()
		local table_ = {
			task = { name = "default:steel_ingot", count = 1 },
			daily = { name = "default:gold_ingot", count = 1 },
			level = { name = "default:gold_ingot", count = 1 },
			stage = { name = "default:diamond", count = 1 },
			module = { name = "default:diamond", count = 3 },
			daily_limit = 5,
		}
		local payload = reports.rewards(table_, {
			{ name = "default:diamond", title = "Diamant" },
			{ name = "default:torch" },
			"nonsense",
		})
		assert.is_true(fits("Rewards", payload))
		assert.are.same(table_, payload.table)
		assert.are.same({ { name = "default:diamond", title = "Diamant" },
			{ name = "default:torch", title = "default:torch" } }, payload.choices)
		assert.is_nil(reports.rewards(table_, {}).choices)
		assert.are.equal("rewards", reports.EVENT_REWARDS)
		assert.are.equal("set_rewards", reports.JOB_SET_REWARDS)
	end)

	it("reads a reward table only if every row is there", function()
		local table_ = {
			task = { name = "a:b", count = 2.9 }, daily = { name = "a:b", count = 1 },
			level = { name = "a:b", count = 1 }, stage = { name = "a:b", count = 1 },
			module = { name = "a:b", count = 1 }, daily_limit = 3, extra = true,
		}
		local read = reports.reward_table(table_)
		assert.are.equal(2, read.task.count)
		assert.is_nil(read.extra)
		table_.stage = nil
		assert.is_nil(reports.reward_table(table_))
		table_.stage = { count = 1 }
		assert.is_nil(reports.reward_table(table_))
		assert.is_nil(reports.reward_table({ daily_limit = "5" }))
		assert.is_nil(reports.reward_table(nil))
	end)
end)
