-- Custom Neotest setup and progress aggregation.

local M = {}

local neotest_loaded = false
local lazy = require("mark.lazy")

local progress = require("mark.neotest_progress")
M.progress_consumer = progress.consumer

function M.augment(tree, args)
	local suppress_notification = args.strategy == "dap"
	if suppress_notification and not require("mark.dap").ensure({ trigger = "neotest dap strategy" }) then
		error("Neotest DAP strategy is unavailable")
	end

	progress.track(tree, suppress_notification)
	return args
end

function M.golang_adapter_config()
	return {
		runner = "gotestsum",
		gotestsum_args = { "--format=standard-quiet" },
		go_test_args = function()
			return { "-coverprofile=" .. vim.uv.cwd() .. "/cover.out" }
		end,
		dap_mode = "manual",
		dap_manual_config = function()
			return {
				name = "Neotest-golang",
				type = "go",
				request = "launch",
				mode = "test",
				outputMode = "remote",
			}
		end,
		-- Neotest already skips dot-directories while scanning.
		filter_dir_patterns = { "**/{node_modules,venv,vendor,dist,build,target}" },
		warn_test_name_dupes = false,
	}
end

function M.ensure(trigger)
	if neotest_loaded then
		return true
	end
	local pack_ok = lazy.packadd_all(
		{ "plenary.nvim", "nvim-nio", "neotest", "neotest-golang", "nvim-coverage" },
		{ notify = true, trigger = trigger or "test keymap" }
	)
	if not pack_ok then
		return false
	end

	local neotest_mod = lazy.require("neotest", { notify = true })
	local neotest_golang = lazy.require("neotest-golang", { notify = true })
	local coverage_mod = lazy.require("coverage", { notify = true })
	if not neotest_mod or not neotest_golang or not coverage_mod then
		return false
	end

	neotest_mod.setup({
		consumers = {
			notification_progress = progress.consumer,
		},
		run = { augment = M.augment },
		adapters = { neotest_golang(M.golang_adapter_config()) },
		discovery = { enabled = false },
		summary = { animated = false },
		output = { open_on_run = false },
	})

	coverage_mod.setup()
	neotest_loaded = true
	return true
end

function M.neotest(trigger)
	if not M.ensure(trigger) then
		return nil
	end
	return require("neotest")
end

function M.coverage(trigger)
	if not M.ensure(trigger) then
		return nil
	end
	return require("coverage")
end

return M
