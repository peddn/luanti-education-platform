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

describe("lep_desk rows", function()
	local students = { "anna", "ben", "mia" }

	it("maps rows to what they stand for", function()
		assert.are.equal(desk.ALL, desk.row_target(1, students))
		assert.are.equal("anna", desk.row_target(2, students))
		assert.are.equal("mia", desk.row_target(4, students))
		assert.is_nil(desk.row_target(5, students))
		assert.is_nil(desk.row_target(0, students))
	end)

	it("finds the row of a target", function()
		assert.are.equal(1, desk.target_row(desk.ALL, students))
		assert.are.equal(2, desk.target_row("anna", students))
		assert.are.equal(4, desk.target_row("mia", students))
		assert.is_nil(desk.target_row("zoe", students))
		assert.is_nil(desk.target_row(nil, students))
	end)

	it("keeps a student called like nothing special apart from the first row", function()
		assert.are.equal(2, desk.target_row("true", { "true" }))
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
