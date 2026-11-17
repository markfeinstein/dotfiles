local function run()
	vim.cmd.packadd("obsidian.nvim")
	assert(vim.fn.executable("node") == 1, "Neovim must provide Node.js for Bases")
	local worker = require("obsidian.bases.worker")
	local status = worker.status()
	assert(status.available, vim.inspect(status.error))

	local done, result, err = false, nil, nil
	worker.evaluate({
		global_filter = 'status == "active"',
		formulas = { score = "priority * 2" },
		rows = {
			{
				note = { status = "active", priority = 2 },
				file = { path = "One.md", name = "One" },
			},
			{
				note = { status = "done", priority = 3 },
				file = { path = "Two.md", name = "Two" },
			},
		},
	}, function(value, failure)
		result, err, done = value, failure, true
	end)
	assert(
		vim.wait(10000, function()
			return done
		end, 10),
		"packaged Bases worker timed out"
	)
	assert(err == nil, vim.inspect(err))
	assert(result.state == "current", vim.inspect(result))
	assert(#result.matches == 1 and result.matches[1].index == 0, vim.inspect(result))
	assert(result.matches[1].formulas.score == 4, vim.inspect(result))
	worker.stop()

	local profile = assert(vim.g.dotfiles_obsidian)
	local configured = assert(profile.workspaces and profile.workspaces[1], "Bases loader test requires a workspace")
	local vault = vim.fs.normalize(vim.fn.expand(configured.path))
	vim.fn.mkdir(vim.fs.joinpath(vault, ".obsidian"), "p")
	local definition = vim.fs.joinpath(vault, "Nested", "Standalone.base")
	local note = vim.fs.joinpath(vault, "Daily.md")
	vim.fn.mkdir(vim.fs.dirname(definition), "p")
	vim.fn.writefile({ "views:", "  - type: table", "    name: Standalone" }, definition)
	vim.fn.writefile({ "![[Standalone.base]]" }, note)

	assert(package.loaded["obsidian"] == nil, "obsidian.nvim should still be lazy before a vault file opens")
	vim.cmd.edit(vim.fn.fnameescape(definition))
	assert(
		vim.wait(3000, function()
			return package.loaded["obsidian"] ~= nil and Obsidian and Obsidian.opts
		end, 20),
		"opening a non-Markdown vault file did not load obsidian.nvim"
	)
	assert(Obsidian.opts.bases.inline.enabled == true, "automatic inline Bases rendering is not configured")
	assert(Obsidian.opts.bases.standalone.auto_open == true, "standalone Base rendering is not configured")

	vim.cmd.edit(vim.fn.fnameescape(note))
	assert(
		vim.wait(3000, function()
			return vim.b.obsidian_buffer == true
		end, 20),
		"Markdown vault behavior did not attach"
	)
	for _, expected in ipairs({
		{ lhs = "<leader>op", desc = "Previous Daily Note" },
		{ lhs = "<leader>on", desc = "Next Daily Note" },
		{ lhs = "<leader>os", desc = "Search Notes" },
	}) do
		local mapping = vim.fn.maparg(expected.lhs, "n", false, true)
		assert(mapping.buffer == 1, expected.lhs .. " must be buffer-local to Markdown notes")
		assert(mapping.desc == expected.desc, expected.lhs .. " must describe its Obsidian action")
	end
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit 1")
else
	print("Packaged Obsidian Bases worker passed")
	vim.cmd("qa!")
end
