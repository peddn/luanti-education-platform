local web_access = dofile("mods/lep_desk/src/web_access.lua")

describe("lep_desk web access", function()
	it("knows what can be an address", function()
		assert.are.equal("anna.muster@schule.example",
			web_access.check_email("  Anna.Muster@Schule.Example "))
		for _, bad in ipairs({
			"", "anna", "anna@", "@schule.example", "anna@schule", "anna@schule..example",
			"anna@.example", "anna@schule.", "an na@schule.example",
			"anna@schule.example\nBcc: x@y.example", "a@b@schule.example",
			string.rep("a", 250) .. "@schule.example",
		}) do
			assert.is_nil(web_access.check_email(bad), bad)
		end
		assert.is_nil(web_access.check_email(nil))
		assert.is_nil(web_access.check_email(5))
	end)

	it("shortens addresses", function()
		assert.are.equal("a…@schule.example", web_access.mask("anna.muster@schule.example"))
		assert.are.equal("ä…@schule.example", web_access.mask("ärger@schule.example"))
		assert.are.equal("…", web_access.mask("broken"))
	end)

	it("derives how a web access stands", function()
		assert.are.equal(web_access.NONE, web_access.status(nil))
		assert.are.equal(web_access.NONE, web_access.status(web_access.record(nil, "")))
		assert.are.equal(web_access.PENDING,
			web_access.status(web_access.record(nil, "a…@schule.example")))
		assert.are.equal(web_access.CONFIRMED,
			web_access.status(web_access.record("a…@schule.example", nil)))
		-- The confirmed address counts while a new one waits.
		assert.are.equal(web_access.CONFIRMED,
			web_access.status(web_access.record("a…@schule.example", "n…@schule.example")))
	end)

	it("shows a request at once", function()
		local none = web_access.record(nil, nil)
		local waiting = web_access.after_request(none, web_access.SET, "anna@schule.example")
		assert.are.same({ pending = "a…@schule.example" }, waiting)

		local confirmed = web_access.record("a…@schule.example", nil)
		local changing = web_access.after_request(confirmed, web_access.SET,
			"neu@schule.example")
		assert.are.same({ address = "a…@schule.example", pending = "n…@schule.example" },
			changing)
		assert.are.same(changing,
			web_access.after_request(changing, web_access.RESEND))
		assert.are.same({}, web_access.after_request(changing, web_access.REMOVE))
		assert.are.same({}, web_access.after_request(nil, web_access.RESEND))
		-- The same address as the confirmed one adds nothing that waits.
		assert.are.same({ address = "a…@schule.example" },
			web_access.after_request(confirmed, web_access.SET, "anna@schule.example"))
	end)

	it("limits how often a mail is asked for", function()
		assert.is_true(web_access.may_ask_for_mail(nil, 1000))
		assert.is_false(web_access.may_ask_for_mail(1000, 1059))
		assert.is_true(web_access.may_ask_for_mail(1000, 1060))
	end)

	it("compares lists of names", function()
		assert.is_true(web_access.same_names({}, {}))
		assert.is_true(web_access.same_names({ "a", "b" }, { "b", "a" }))
		assert.is_false(web_access.same_names({ "a" }, { "a", "b" }))
		assert.is_false(web_access.same_names({ "a", "b" }, { "a", "c" }))
	end)
end)
