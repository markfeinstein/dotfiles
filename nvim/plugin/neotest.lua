-- Neotest with Go and coverage support.

local config = require("mark.neotest")

local function neotest()
	return config.neotest("test keymap")
end

local function coverage()
	return config.coverage("coverage keymap")
end

local function current_file()
	return vim.fn.expand("%")
end

local function call(method, arg)
	local path = vim.split(method, ".", { plain = true })
	return function(mod)
		local fn = vim.tbl_get(mod, unpack(path))
		if type(arg) == "function" then
			fn(arg())
		elseif arg ~= nil then
			-- Plugins may mutate options; each invocation owns a fresh table.
			fn(vim.deepcopy(arg))
		else
			fn()
		end
	end
end

-- Keymaps (eager; callbacks packadd optional plugins before requiring modules)
local function map_loaded(load, lhs, desc, fn)
	vim.keymap.set("n", lhs, function()
		local mod = load()
		if mod then
			fn(mod)
		end
	end, { desc = desc })
end

local neotest_keymaps = {
	{ "<leader>tr", "Run Nearest", call("run.run") },
	{ "<leader>tt", "Run File", call("run.run", current_file) },
	{ "<leader>tT", "Run All Test Files", call("run.run", function()
		return vim.uv.cwd()
	end) },
	{ "<leader>tl", "Run Last", call("run.run_last") },
	{ "<leader>tR", "Run Nearest (Race Detector)", call("run.run", { extra_args = { "-race" } }) },
	{ "<leader>tN", "Run Nearest (No Cache)", call("run.run", { extra_args = { "-count=1" } }) },
	{ "<leader>ta", "Attach to Test", call("run.attach") },
	{ "<leader>tS", "Stop", call("run.stop") },
	{ "<leader>tw", "Toggle Watch", call("watch.toggle", current_file) },
	{ "<leader>ts", "Toggle Summary", call("summary.toggle") },
	{ "<leader>to", "Show Output", call("output.open", { enter = true, auto_close = true }) },
	{ "<leader>tO", "Toggle Output Panel", call("output_panel.toggle") },
	{ "]t", "Next Test", call("jump.next") },
	{ "[t", "Previous Test", call("jump.prev") },
	{ "]T", "Next Failed Test", call("jump.next", { status = "failed" }) },
	{ "[T", "Previous Failed Test", call("jump.prev", { status = "failed" }) },
}

for _, map in ipairs(neotest_keymaps) do
	map_loaded(neotest, map[1], map[2], map[3])
end

vim.keymap.set("n", "<leader>td", function()
	if not require("mark.dap").ensure({ trigger = "test debug keymap" }) then
		return
	end
	local nt = neotest()
	if nt then
		nt.run.run({ strategy = "dap" })
	end
end, { desc = "Debug Nearest" })

local coverage_keymaps = {
	{ "<leader>tc", "Coverage in Gutter", call("load", true) },
	{
		"<leader>tC",
		"Coverage Summary",
		function(cov)
			cov.load(false)
			cov.summary()
		end,
	},
}

for _, map in ipairs(coverage_keymaps) do
	map_loaded(coverage, map[1], map[2], map[3])
end
