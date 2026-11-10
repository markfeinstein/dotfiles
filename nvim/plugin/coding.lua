-- Formatting

local lazy = require("mark.lazy")

local conform_config = require("mark.conform")
local conform_opts = conform_config.opts

vim.g.format_on_save = true

local ensure_conform = lazy.setup_once("conform.nvim", "conform", function(conform)
	conform.setup(conform_opts)
	vim.o.formatexpr = conform.formatexpr
end, "BufWritePre/format keymap")

vim.keymap.set({ "n", "x" }, "<leader>cf", function()
	if not ensure_conform() then
		return
	end
	require("conform").format({ async = true })
end, { desc = "Format" })

vim.api.nvim_create_autocmd("BufWritePre", {
	group = vim.api.nvim_create_augroup("conform_format_on_save"),
	callback = function(ev)
		local ft = vim.bo[ev.buf].filetype
		if not vim.g.format_on_save or vim.bo[ev.buf].buftype ~= "" or not conform_config.should_format_on_save(ft) then
			return
		end
		if not ensure_conform() then
			return
		end
		require("conform").format({ bufnr = ev.buf, timeout_ms = 500 })
	end,
	desc = "Format on save",
})

-- Linting

local tooling = vim.g.dotfiles_neovim_tooling or {}
local linters_by_ft = {}
if tooling.go then
	linters_by_ft.go = { "golangcilint" }
end
if tooling.sql then
	for _, filetype in ipairs({ "mysql", "plsql", "sql" }) do
		linters_by_ft[filetype] = { "sqlfluff" }
	end
end

vim.g.golangci_lint_on_save = false

local timer = require("mark.timer")
local lint_timers = {}
local ensure_lint = lazy.setup_once("nvim-lint", "lint", function(lint)
	lint.linters_by_ft = linters_by_ft
end, "BufWritePost")

local function lint_buffer(buf)
	if
		not vim.api.nvim_buf_is_valid(buf)
		or not vim.api.nvim_buf_is_loaded(buf)
		or not linters_by_ft[vim.bo[buf].filetype]
	then
		return
	end
	if _G._ensure_diagnostics then
		_G._ensure_diagnostics()
	end
	if not ensure_lint() then
		return
	end
	vim.api.nvim_buf_call(buf, function()
		require("lint").try_lint()
	end)
end

local function cancel_pending_lint(buf)
	timer.cancel_slot(lint_timers, buf)
end

local function lint_current_buffer()
	local buf = vim.api.nvim_get_current_buf()
	cancel_pending_lint(buf)
	lint_buffer(buf)
end

vim.api.nvim_create_user_command("Lint", lint_current_buffer, { desc = "Lint current buffer", force = true })
vim.keymap.set("n", "<leader>cl", lint_current_buffer, { desc = "Lint current buffer" })

local lint_group = vim.api.nvim_create_augroup("coding_lint")
vim.api.nvim_create_autocmd("BufWritePost", {
	group = lint_group,
	callback = function(ev)
		local ft = vim.bo[ev.buf].filetype
		if not linters_by_ft[ft] or (ft == "go" and not vim.g.golangci_lint_on_save) then
			cancel_pending_lint(ev.buf)
			return
		end
		timer.replace(lint_timers, ev.buf, 750, function()
			if not vim.api.nvim_buf_is_valid(ev.buf) or not vim.api.nvim_buf_is_loaded(ev.buf) then
				return
			end
			local current_ft = vim.bo[ev.buf].filetype
			if not linters_by_ft[current_ft] or (current_ft == "go" and not vim.g.golangci_lint_on_save) then
				return
			end
			lint_buffer(ev.buf)
		end)
	end,
	desc = "Lint on write after a debounce",
})

vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
	group = lint_group,
	callback = function(ev)
		cancel_pending_lint(ev.buf)
	end,
	desc = "Cancel pending lint for unloaded buffer",
})

-- Debugging

local function ensure_dap()
	return require("mark.dap").ensure({ trigger = "debug keymap" })
end

local function refresh_debug_signs(buf)
	local statuscolumn = rawget(_G, "_statuscolumn")
	if statuscolumn and type(statuscolumn.invalidate) == "function" then
		statuscolumn.invalidate(buf)
	end
end

local function set_breakpoint_at(buf, line, opts)
	if not vim.api.nvim_buf_is_valid(buf) then
		vim.notify("Cannot set breakpoint: source buffer is no longer valid", vim.log.levels.WARN)
		return
	end

	local dap = require("dap")
	local breakpoints = require("dap.breakpoints")
	breakpoints.set(opts, buf, line)
	local buffer_breakpoints = breakpoints.get(buf)
	local function sync_session(session)
		session:set_breakpoints(buffer_breakpoints)
		for _, child in pairs(session.children or {}) do
			sync_session(child)
		end
	end
	for _, session in pairs(dap.sessions()) do
		sync_session(session)
	end
	if vim.fn.getqflist({ title = 1 }).title == "DAP Breakpoints" then
		dap.list_breakpoints(false)
	end
	refresh_debug_signs(buf)
end

local function visible_debug_variable_instruction()
	local phrases = {
		"`s`  Set the value of a variable",
		"`s`  Set the value of an expression or variable",
	}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
			for _, phrase in ipairs(phrases) do
				if line:find(phrase, 1, true) then
					return true
				end
			end
		end
	end
	return false
end

local function open_debug_scopes_for_variable_edit()
	if not ensure_dap() then
		return
	end

	local dap = require("dap")
	local session = dap.session()
	if not session then
		vim.notify("No active debug session", vim.log.levels.INFO)
		return
	end
	if not session.stopped_thread_id then
		vim.notify("Pause the debug session before editing variables", vim.log.levels.INFO)
		return
	end

	local dap_view = lazy.require("dap-view", { notify = true })
	if not dap_view then
		return
	end
	dap_view.open()
	dap_view.jump_to_view("scopes")

	if not visible_debug_variable_instruction() then
		vim.notify("In dap-view Scopes, press `s` on a variable to set its value", vim.log.levels.INFO)
	end
end

-- Keymap callback that loads nvim-dap first, then calls require("dap")[method]().
local function dap_call(method)
	return function()
		if ensure_dap() then
			require("dap")[method]()
		end
	end
end

local function dap_prompt_breakpoint(prompt, option_key)
	return function()
		if not ensure_dap() then
			return
		end
		local buf = vim.api.nvim_get_current_buf()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		vim.ui.input({ prompt = prompt, scope = "line" }, function(input)
			if input ~= nil then
				set_breakpoint_at(buf, line, { [option_key] = input })
			end
		end)
	end
end

local dap_keymaps = {
	{
		mode = "n",
		lhs = "<leader>db",
		rhs = function()
			if not ensure_dap() then
				return
			end
			local buf = vim.api.nvim_get_current_buf()
			require("dap").toggle_breakpoint()
			refresh_debug_signs(buf)
		end,
		desc = "Toggle Breakpoint",
	},
	{
		mode = "n",
		lhs = "<leader>dB",
		rhs = dap_prompt_breakpoint("Breakpoint condition: ", "condition"),
		desc = "Set Conditional Breakpoint",
	},
	{ mode = "n", lhs = "<leader>dc", rhs = dap_call("continue"), desc = "Continue" },
	{ mode = "n", lhs = "<leader>dd", rhs = dap_call("disconnect"), desc = "Disconnect" },
	{ mode = "n", lhs = "<leader>dn", rhs = dap_call("step_over"), desc = "Step Over" },
	{ mode = "n", lhs = "<leader>di", rhs = dap_call("step_into"), desc = "Step Into" },
	{ mode = "n", lhs = "<leader>do", rhs = dap_call("step_out"), desc = "Step Out" },
	{
		mode = "n",
		lhs = "<leader>dL",
		rhs = dap_prompt_breakpoint("Log point message: ", "log_message"),
		desc = "Set Logpoint",
	},
	{
		mode = { "n", "x" },
		lhs = "<leader>dw",
		rhs = function()
			if not ensure_dap() then
				return
			end
			local dap_view = lazy.require("dap-view", { notify = true })
			if dap_view then
				dap_view.add_expr()
			end
		end,
		desc = "Add Watch",
	},
	{
		mode = "n",
		lhs = "<leader>dv",
		rhs = open_debug_scopes_for_variable_edit,
		desc = "Edit Variable in Scopes",
	},
	{
		mode = "n",
		lhs = "<leader>dr",
		rhs = function()
			if ensure_dap() then
				require("dap").repl.toggle()
			end
		end,
		desc = "Toggle REPL",
	},
	{ mode = "n", lhs = "<leader>dt", rhs = dap_call("terminate"), desc = "Terminate" },
	{ mode = "n", lhs = "<leader>dl", rhs = dap_call("run_last"), desc = "Run Last Debug Session" },
}

for _, keymap in ipairs(dap_keymaps) do
	vim.keymap.set(keymap.mode, keymap.lhs, keymap.rhs, { desc = keymap.desc })
end

-- Diagnostics UI

local ensure_trouble = lazy.setup_once("trouble.nvim", "trouble", function(trouble)
	trouble.setup({
		auto_close = true,
		auto_jump = true,
	})
end, "diagnostics keymap")

local function trouble_toggle(opts)
	return function()
		if ensure_trouble() then
			require("trouble").toggle(opts)
		end
	end
end

local trouble_keymaps = {
	{ mode = "n", lhs = "<leader>xx", rhs = trouble_toggle("diagnostics"), desc = "Toggle Trouble (All Diagnostics)" },
	{
		mode = "n",
		lhs = "<leader>xd",
		rhs = trouble_toggle({ mode = "diagnostics", filter = { buf = 0 } }),
		desc = "Document Diagnostics",
	},
	{ mode = "n", lhs = "<leader>xl", rhs = trouble_toggle("loclist"), desc = "Location List" },
	{ mode = "n", lhs = "<leader>xq", rhs = trouble_toggle("qflist"), desc = "Quickfix List" },
}

for _, keymap in ipairs(trouble_keymaps) do
	vim.keymap.set(keymap.mode, keymap.lhs, keymap.rhs, { desc = keymap.desc })
end
