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
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit 1")
else
	print("Packaged Obsidian Bases worker passed")
	vim.cmd("qa!")
end
