local formspec = dofile("mods/lep_core/src/formspec.lua")

describe("lep_core formspec", function()
	it("escapes the characters that have a meaning in formspecs", function()
		assert.are.equal("a\\, b\\; c \\[d\\] \\\\ e", formspec.escape("a, b; c [d] \\ e"))
		assert.are.equal("plain text", formspec.escape("plain text"))
		assert.are.equal("42", formspec.escape(42))
	end)

	it("starts with version and size", function()
		assert.are.equal("formspec_version[6]size[10.5,9]", formspec.new(10.5, 9):build())
	end)

	it("adds a title that stands out, with a line below it", function()
		local fs = formspec.new(9, 5):title("Hi; [you]"):label(0.375, 2, "text"):build()
		assert.are.equal("formspec_version[6]size[9,5]"
			.. "style_type[label;font=bold;font_size=*1.3]"
			.. "label[0.375,0.6;Hi\\; \\[you\\]]"
			.. "style_type[label;font=normal;font_size=*1]"
			.. "box[0.375,1.05;8.25,0.03;#FFFFFF80]"
			.. "label[0.375,2;text]", fs)
		assert.is_true(formspec.CONTENT_TOP > 1.05)
	end)

	it("adds headings and large text and sets the font back", function()
		local fs = formspec.new(9, 5):heading(1, 2, "Part [1]"):big_label(1, 3, "3 + 4"):build()
		assert.is_truthy(fs:find("style_type[label;font=bold]label[1,2;Part \\[1\\]]"
			.. "style_type[label;font=normal]", 1, true))
		assert.is_truthy(fs:find("style_type[label;font_size=*1.6]label[1,3;3 + 4]"
			.. "style_type[label;font_size=*1]", 1, true))
	end)

	it("makes buttons stand out in one of two colours", function()
		local fs = formspec.new(9, 5)
			:highlight("on", formspec.ACTIVE):button(1, 1, 2, 0.8, "on", "On")
			:highlight("back", formspec.OTHER):button(1, 2, 2, 0.8, "back", "Back")
			:build()
		assert.is_truthy(fs:find("style[on;bgcolor=#30C030]button[1,1;2,0.8;on;On]", 1, true))
		assert.is_truthy(fs:find("style[back;bgcolor=#B05A2A]button[1,2;2,0.8;back;Back]", 1, true))
		assert.has_error(function() formspec.new(9, 5):highlight("x", "pink") end)
	end)

	it("puts the button that closes the window into the bottom right corner", function()
		local fs = formspec.new(9, 5):close("Close"):build()
		assert.is_truthy(fs:find("button_exit[6.625,3.825;2,0.8;close;Close]", 1, true))
	end)

	it("adds a line across the window", function()
		local fs = formspec.new(6, 5):separator(3):build()
		assert.is_truthy(fs:find("box[0.375,3;5.25,0.03;#FFFFFF80]", 1, true))
	end)

	it("joins the parts of an element", function()
		local fs = formspec.new(4, 3):element("box", { 0, 0 }, { 4, 3 }, "#000000"):build()
		assert.are.equal("formspec_version[6]size[4,3]box[0,0;4,3;#000000]", fs)
	end)

	it("escapes label text", function()
		local fs = formspec.new(4, 3):label(0.5, 1, "Hi; [you], ok"):build()
		assert.is_truthy(fs:find("label[0.5,1;Hi\\; \\[you\\]\\, ok]", 1, true))
	end)

	it("adds lists and list rings", function()
		local fs = formspec.new(10.5, 9)
			:list("detached:chest_a", "main", 0.375, 1, 8, 2)
			:list("current_player", "main", 0.375, 4, 8, 4)
			:listring("detached:chest_a", "main")
			:listring("current_player", "main")
			:build()
		assert.is_truthy(fs:find("list[detached:chest_a;main;0.375,1;8,2]", 1, true))
		assert.is_truthy(fs:find("list[current_player;main;0.375,4;8,4]", 1, true))
		assert.is_truthy(fs:find("listring[detached:chest_a;main]listring[current_player;main]",
			1, true))
	end)

	it("adds a text list with escaped lines", function()
		local fs = formspec.new(8, 6)
			:textlist(0.5, 1, 7, 3, "list", { "Gold, big", "Silver [2]", "Bronze" }, 2)
			:build()
		assert.is_truthy(fs:find(
			"textlist[0.5,1;7,3;list;Gold\\, big,Silver \\[2\\],Bronze;2]", 1, true))
	end)

	it("adds tables with columns", function()
		local fs = formspec.new(8, 6)
			:table(0.5, 1, 7, 3, "people", { "color", "text", "text,padding=1" }, {
				{ "#FFFFFF", "[x]", "anna, the first" },
				{ "#BBBBBB", "[ ]", "ben" },
			}, 2)
			:build()
		assert.is_truthy(fs:find("tablecolumns[color;text;text,padding=1]", 1, true))
		assert.is_truthy(fs:find(
			"table[0.5,1;7,3;people;#FFFFFF,\\[x\\],anna\\, the first,#BBBBBB,\\[ \\],ben;2]",
			1, true))
	end)

	it("rejects table rows that do not fit the columns", function()
		assert.has_error(function()
			formspec.new(8, 6):table(0, 0, 1, 1, "t", { "text", "text" }, { { "only one" } })
		end)
		assert.has_error(function()
			formspec.new(8, 6):table(0, 0, 1, 1, "t", {}, {})
		end)
	end)

	it("adds buttons", function()
		local fs = formspec.new(8, 6)
			:button(0.5, 5, 3, 0.8, "place", "Put it here")
			:button_exit(4, 5, 3, 0.8, "close", "Close")
			:build()
		assert.is_truthy(fs:find("button[0.5,5;3,0.8;place;Put it here]", 1, true))
		assert.is_truthy(fs:find("button_exit[4,5;3,0.8;close;Close]", 1, true))
	end)

	it("adds an input field that submits on Enter", function()
		local fs = formspec.new(8, 4)
			:field(0.5, 1, 4, 0.8, "answer", "Your answer", "a;b")
			:submit_on_enter("answer")
			:build()
		assert.is_truthy(fs:find("field[0.5,1;4,0.8;answer;Your answer;a\\;b]", 1, true))
		assert.is_truthy(fs:find("field_close_on_enter[answer;false]", 1, true))
		assert.is_truthy(fs:find("set_focus[answer;true]", 1, true))
	end)

	it("cannot be broken out of by a name", function()
		local fs = formspec.new(4, 3):list("detached:x]button[0,0;1,1;a;b", "main", 0, 0, 1, 1)
			:build()
		assert.is_nil(fs:find("]button[", 1, true))
	end)

	it("knows the size of a row of slots", function()
		assert.are.equal(1, formspec.slots(1))
		assert.are.equal(9.75, formspec.slots(8))
		assert.are.equal(4.75, formspec.slots(4))
	end)
end)
