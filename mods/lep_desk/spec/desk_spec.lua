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
		actions:register("one", { title = "Jump", privilege = "p", run = function() end,
			single = true })
		assert.is_true(actions:get("one").single)
		assert.is_false(actions:get("plain").single)
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

	it("arranges plain actions below each other and groups in columns", function()
		local list = {
			{ id = "a" }, { id = "t1", group = "Time" }, { id = "b" },
			{ id = "t2", group = "Time" }, { id = "t3", group = "Time" },
			{ id = "t4", group = "Time" }, { id = "c1", group = "Chat" },
		}
		local items, bottom = desk.layout(list, 10, 1, 6.4)
		local function near(a, b) return math.abs(a - b) < 1e-9 end
		local pitch, small, heading = desk.BUTTON_PITCH, desk.SMALL_PITCH, desk.HEADING_HEIGHT

		-- The two plain actions, full width.
		assert.are.same({ kind = "button", index = 1, x = 10, y = 1, width = 6.4,
			height = desk.BUTTON_HEIGHT }, items[1])
		assert.are.equal(3, items[2].index)
		assert.is_true(near(items[2].y, 1 + pitch))

		-- The first group: heading, then three buttons side by side, the
		-- fourth starts a new row.
		local top = 1 + 2 * pitch
		assert.are.equal("heading", items[3].kind)
		assert.are.equal("Time", items[3].text)
		assert.is_true(near(items[3].y, top + heading / 2))
		local row = top + heading
		assert.are.equal(2, items[4].index)
		assert.is_true(near(items[4].x, 10) and near(items[4].y, row))
		assert.is_true(near(items[4].width, 2) and near(items[4].height, desk.SMALL_HEIGHT))
		assert.is_true(near(items[5].x, 12.2) and near(items[5].y, row))
		assert.is_true(near(items[6].x, 14.4) and near(items[6].y, row))
		assert.are.equal(6, items[7].index)
		assert.is_true(near(items[7].x, 10) and near(items[7].y, row + small))

		-- The next group follows below the last row.
		local next_top = row + 2 * small
		assert.are.equal("Chat", items[8].text)
		assert.is_true(near(items[8].y, next_top + heading / 2))
		assert.is_true(near(items[9].y, next_top + heading))
		assert.is_true(near(bottom, next_top + heading + small))
		assert.are.equal(9, #items)
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
