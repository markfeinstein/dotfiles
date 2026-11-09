local M = {}

local lazy = require("mark.lazy")

local dap_loaded = false

local core_plugins = {
	"nvim-dap",
	"nvim-dap-go",
}

local function setup_optional(plugin, module_name, trigger, setup)
	if not lazy.packadd(plugin, { notify = true, trigger = trigger }) then
		return false
	end
	local mod = lazy.require(module_name, { notify = true })
	if not mod then
		return false
	end
	local ok, err = pcall(setup, mod)
	if not ok then
		vim.notify(("failed to configure %s: %s"):format(plugin, err), vim.log.levels.ERROR)
		return false
	end
	return true
end

local function apply_debug_virtual_text_highlights()
	local apply = rawget(_G, "_apply_debug_virtual_text_highlights")
	if type(apply) == "function" then
		apply()
	end
end

local function apply_dap_view_winbar_highlights()
	local apply = rawget(_G, "_apply_dap_view_winbar_highlights")
	if type(apply) == "function" then
		apply()
	end
end

local function install_dap_view_lifecycle(dap, dap_view)
	for _, event in ipairs({ "attach", "launch" }) do
		dap.listeners.before[event].dotfiles_dap_view = function()
			dap_view.open()
		end
	end

	for _, event in ipairs({ "disconnect", "event_terminated" }) do
		dap.listeners.before[event].dotfiles_dap_view = function()
			if vim.v.exitreason == "" and vim.tbl_count(dap.sessions()) <= 1 then
				dap_view.close(true)
			end
		end
	end
end

function M.ensure(opts)
	if dap_loaded then
		return true
	end

	local trigger = (opts and opts.trigger) or "debug keymap"
	local pack_ok = lazy.packadd_all(core_plugins, { notify = true, trigger = trigger })
	if not pack_ok then
		return false
	end

	local dap = lazy.require("dap", { notify = true })
	local dap_go = lazy.require("dap-go", { notify = true })
	if not dap or not dap_go then
		return false
	end

	local dap_icons = icons.dap
	local signs = {
		DapStopped = {
			text = dap_icons.Stopped,
			texthl = "DapStopped",
			linehl = "DapStoppedLine",
			numhl = "DapStopped",
		},
		DapBreakpoint = { text = dap_icons.Breakpoint, texthl = "DapBreakpoint" },
		DapBreakpointCondition = { text = dap_icons.BreakpointCondition, texthl = "DapBreakpointCondition" },
		DapBreakpointRejected = { text = dap_icons.BreakpointRejected, texthl = "DiagnosticError" },
		DapLogPoint = { text = dap_icons.LogPoint, texthl = "DiagnosticInfo" },
	}

	for name, sign in pairs(signs) do
		vim.fn.sign_define(name, sign)
	end

	local dap_go_ok, dap_go_err = pcall(dap_go.setup)
	if not dap_go_ok then
		vim.notify("failed to configure nvim-dap-go: " .. tostring(dap_go_err), vim.log.levels.ERROR)
		return false
	end

	-- Keep the global 'usetab' preference, but let DAP open stopped source buffers
	-- when the adapter reports a frame that is not visible in any current tab.
	dap.defaults.fallback.switchbuf = "usetab,uselast"
	-- Delve advertises exception filters that it later rejects and supports native
	-- restart, which does not restart Go test debugging from the beginning. Scrub
	-- those capabilities from the initialize response before nvim-dap or dap-view
	-- caches them.
	dap.listeners.before.initialize.dotfiles_go_initialize_capabilities = function(session, err, result)
		if err or type(result) ~= "table" or not session or not session.config or session.config.type ~= "go" then
			return
		end

		result.exceptionBreakpointFilters = nil
		if session.config.mode == "test" then
			result.supportsRestartRequest = false
		end
	end

	local function invalidate_statuscolumn()
		local statuscolumn = rawget(_G, "_statuscolumn")
		if statuscolumn and type(statuscolumn.invalidate) == "function" then
			statuscolumn.invalidate()
		end
	end
	for _, event in ipairs({
		"event_stopped",
		"event_continued",
		"event_breakpoint",
		"event_exited",
		"event_terminated",
		"setBreakpoints",
		"disconnect",
	}) do
		dap.listeners.after[event].dotfiles_statuscolumn = invalidate_statuscolumn
	end
	dap.listeners.on_session.dotfiles_statuscolumn = function(_, new_session)
		if new_session then
			new_session.on_close.dotfiles_statuscolumn = vim.schedule_wrap(invalidate_statuscolumn)
		end
	end

	setup_optional("nvim-dap-virtual-text", "nvim-dap-virtual-text", trigger, function(dap_virtual_text)
		dap_virtual_text.setup({
			-- Delimit inline values so they read as an overlay on the code instead
			-- of another token in the expression. Values stay whole; nothing is
			-- truncated, and brackets keep the cell width unambiguous.
			display_callback = function(variable, _, _, _, opts)
				local value = tostring(variable.value or ""):gsub("%s+", " ")
				if opts.virt_text_pos == "inline" then
					return (" [%s] "):format(value)
				end
				return ("[%s = %s]"):format(variable.name, value)
			end,
		})
		apply_debug_virtual_text_highlights()
	end)

	local step_back_icon = ""
	local function supports_step_back(session)
		return session and session.capabilities and session.capabilities.supportsStepBack == true
	end
	setup_optional("nvim-dap-view", "dap-view", trigger, function(dap_view)
		dap_view.setup({
			winbar = {
				-- Half-circle caps turn each section into a pill, the same shape the
				-- statusline mode indicator uses.
				separators = { icons.symbols.left, icons.symbols.right },
				controls = {
					enabled = true,
					custom_buttons = {
						step_back = {
							render = function(session)
								if not supports_step_back(session) then
									return ""
								end
								local group = session.stopped_thread_id and "ControlStepBack" or "ControlNC"
								return ("%%#NvimDapView%s#%s%%*"):format(group, step_back_icon)
							end,
							action = function()
								if supports_step_back(dap.session()) then
									dap.step_back()
								end
							end,
						},
					},
				},
			},
			windows = { terminal = { hide = { "go" } } },
			auto_toggle = false,
		})
		install_dap_view_lifecycle(dap, dap_view)
		require("mark.compat.dap_view").install_scopes_refresh(dap)
		apply_debug_virtual_text_highlights()
		apply_dap_view_winbar_highlights()
	end)

	dap_loaded = true
	return true
end

return M
