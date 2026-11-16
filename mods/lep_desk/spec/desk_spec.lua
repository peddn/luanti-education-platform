local desk = dofile("mods/lep_desk/src/desk.lua")

local function action(privilege)
	return { title = "Do it", privilege = privilege, run = function() end }
end

describe("lep_desk actions", function()
	it("keeps actions in the order they were registered", function()
		local actions = desk.new_actions()
		actions:register("b:second", action("p1"))
		actions:register("a:first", action("p1"))
		local list = actions:allowed(function() return true end)
		assert.are.equal("b:second", list[1].id)
		assert.are.equal("a:first", list[2].id)
		assert.are.equal("Do it", actions:get("a:first").title)
		assert.is_nil(actions:get("unknown"))
	end)

	it("shows a teacher only the actions they may use", function()
		local actions = desk.new_actions()
		actions:register("a", action("send"))
		actions:register("b", action("freeze"))
		actions:register("c", action("send"))
		local list = actions:allowed(function(privilege) return privilege == "send" end)
		assert.are.equal(2, #list)
		assert.are.equal("a", list[1].id)
		assert.are.equal("c", list[2].id)
		assert.are.same({}, actions:allowed(function() return false end))
	end)

	it("keeps the optional fields of an action", function()
		local actions = desk.new_actions()
		actions:register("plain", action("p"))
		actions:register("world", {
			title = "Noon", privilege = "p", run = function() end,
			needs_targets = false, group = "Time", is_active = function() return true end,
		})
		assert.is_true(actions:get("plain").needs_targets)
		assert.is_nil(actions:get("plain").group)
		assert.is_false(actions:get("world").needs_targets)
		assert.are.equal("Time", actions:get("world").group)
		assert.is_true(actions:get("world").is_active())
		assert.has_error(function()
			actions:register("x", { title = "x", privilege = "p", run = function() end,
				group = "" })
		end)
		assert.has_error(function()
			actions:register("y", { title = "y", privilege = "p", run = function() end,
				is_active = true })
		end)
	end)

	it("arranges plain actions below each other and groups in two columns", function()
		local list = {
			{ id = "a" }, { id = "t1", group = "Time" }, { id = "b" },
			{ id = "t2", group = "Time" }, { id = "t3", group = "Time" },
		}
		local items, bottom = desk.layout(list, 10, 1, 5)
		assert.are.same({ kind = "button", index = 1, x = 10, y = 1, width = 5, height = 0.8 },
			items[1])
		assert.are.same({ kind = "button", index = 3, x = 10, y = 2, width = 5, height = 0.8 },
			items[2])
		assert.are.same({ kind = "heading", text = "Time", x = 10, y = 3.375 }, items[3])
		assert.are.same({ kind = "button", index = 2, x = 10, y = 3.75, width = 2.4,
			height = 0.7 }, items[4])
		assert.are.equal(12.6, items[5].x)
		assert.are.equal(3.75, items[5].y)
		assert.are.equal(4, items[5].index)
		assert.are.equal(10, items[6].x)
		assert.is_true(math.abs(items[6].y - 4.6) < 1e-9)
		assert.is_true(math.abs(bottom - 5.45) < 1e-9)
		assert.are.equal(6, #items)
	end)

	it("arranges nothing for no actions", function()
		local items, bottom = desk.layout({}, 10, 1, 5)
		assert.are.same({}, items)
		assert.are.equal(1, bottom)
	end)

	it("rejects incomplete definitions", function()
		local actions = desk.new_actions()
		actions:register("a", action("p"))
		assert.has_error(function() actions:register("a", action("p")) end)
		assert.has_error(function() actions:register("", action("p")) end)
		assert.has_error(function() actions:register("b", { title = "x", privilege = "p" }) end)
		assert.has_error(function()
			actions:register("c", { title = "x", run = function() end })
		end)
		assert.has_error(function()
			actions:register("d", { privilege = "p", run = function() end })
		end)
	end)
end)

describe("lep_desk students", function()
	it("lists the online players without a desk, sorted", function()
		local teachers = { teacher = true }
		local list = desk.students({ "mia", "teacher", "ben", "anna" }, function(name)
			return teachers[name] == true
		end)
		assert.are.same({ "anna", "ben", "mia" }, list)
	end)
end)

describe("lep_desk list", function()
	it("finds a student in the list", function()
		local students = { "anna", "ben", "mia" }
		assert.are.equal(1, desk.index_of("anna", students))
		assert.are.equal(3, desk.index_of("mia", students))
		assert.is_nil(desk.index_of("zoe", students))
		assert.is_nil(desk.index_of(nil, students))
	end)
end)

describe("lep_desk selection", function()
	local students = { "anna", "ben", "mia" }

	it("starts with all students", function()
		local selection = desk.new_selection()
		assert.are.same(students, desk.targets(selection, students))
		assert.is_true(desk.is_selected(selection, "anna"))
	end)

	it("includes students who join later while all are selected", function()
		local selection = desk.new_selection()
		assert.are.same({ "anna", "ben", "mia", "zoe" },
			desk.targets(selection, { "anna", "ben", "mia", "zoe" }))
	end)

	it("switches between all and nobody", function()
		local selection = desk.toggle_all(desk.new_selection())
		assert.are.same({}, desk.targets(selection, students))
		selection = desk.toggle_all(selection)
		assert.are.same(students, desk.targets(selection, students))
	end)

	it("takes one student out of all", function()
		local selection = desk.toggle(desk.new_selection(), "ben", students)
		assert.is_false(selection.all)
		assert.are.same({ "anna", "mia" }, desk.targets(selection, students))
	end)

	it("marks single students", function()
		local selection = desk.toggle_all(desk.new_selection())
		selection = desk.toggle(selection, "mia", students)
		selection = desk.toggle(selection, "anna", students)
		assert.are.same({ "anna", "mia" }, desk.targets(selection, students))
		selection = desk.toggle(selection, "mia", students)
		assert.are.same({ "anna" }, desk.targets(selection, students))
	end)

	it("turns into all when everybody is marked", function()
		local selection = desk.toggle_all(desk.new_selection())
		for _, name in ipairs(students) do
			selection = desk.toggle(selection, name, students)
		end
		assert.is_true(selection.all)
	end)

	it("selects nobody", function()
		assert.are.same({}, desk.targets(desk.select_none(), students))
	end)

	it("selects exactly the given students", function()
		local selection = desk.select_names({ "mia", "zoe", "anna" }, students)
		assert.are.same({ "anna", "mia" }, desk.targets(selection, students))
		assert.is_false(selection.all)
		assert.is_true(desk.select_names({ "anna", "ben", "mia" }, students).all)
		assert.are.same({}, desk.targets(desk.select_names({}, students), students))
	end)

	it("inverts a selection", function()
		local selection = desk.select_names({ "ben" }, students)
		assert.are.same({ "anna", "mia" },
			desk.targets(desk.invert(selection, students), students))
		assert.are.same({}, desk.targets(desk.invert(desk.new_selection(), students), students))
		assert.is_true(desk.invert(desk.select_none(), students).all)
		assert.are.same({}, desk.targets(desk.invert(desk.select_none(), {}), {}))
	end)

	it("does not change the selection it was given", function()
		local selection = desk.new_selection()
		desk.toggle(selection, "ben", students)
		desk.toggle_all(selection)
		assert.is_true(selection.all)
	end)

	it("leaves out selected students who are gone", function()
		local selection = desk.toggle_all(desk.new_selection())
		selection = desk.toggle(selection, "ben", students)
		selection = desk.toggle(selection, "mia", students)
		assert.are.same({ "mia" }, desk.targets(selection, { "anna", "mia" }))
	end)

	it("selects nobody when there are no students", function()
		assert.are.same({}, desk.targets(desk.new_selection(), {}))
		assert.is_false(desk.toggle(desk.toggle_all(desk.new_selection()), "x", {}).all)
	end)
end)
