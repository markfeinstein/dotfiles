local lazy = require("mark.lazy")
local fzf_config = require("mark.fzf")
local fzf_window = require("mark.fzf_window")

local fzf_setup_done = false
local select_fallback = vim.ui.select
local select_loader
local select_loading = false

local function with_real_select(body)
	local current_select = vim.ui.select
	if select_loader and current_select == select_loader then
		vim.ui.select = select_fallback
	end
	local ok, result = pcall(body)
	if select_loader and current_select == select_loader and vim.ui.select == select_fallback then
		vim.ui.select = select_loader
	end
	if not ok then
		error(result, 0)
	end
	return result
end

local function call_select_fallback(items, opts, on_choice)
	return with_real_select(function()
		return select_fallback(items, opts, on_choice)
	end)
end

local function has_treesitter_symbols(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local filetype = vim.bo[bufnr].filetype
	if filetype == "" then
		return false
	end
	local language = vim.treesitter.language.get_lang(filetype) or filetype
	local query_ok, query = pcall(vim.treesitter.query.get, language, "locals")
	if not query_ok or not query then
		return false
	end
	return pcall(vim.treesitter.get_parser, bufnr, language)
end

local function global_picker_modes()
	local context = require("fzf-lua.utils").CTX()
	local bufnr = context and context.bufnr or vim.api.nvim_get_current_buf()
	local symbol_clients = vim.lsp.get_clients({
		bufnr = bufnr,
		method = "textDocument/documentSymbol",
	})

	local pickers = {
		{ "smart", desc = "Smart" },
		{ "buffers", desc = "Open files", prefix = "$" },
	}
	if #symbol_clients > 0 then
		pickers[#pickers + 1] = {
			"lsp_document_symbols",
			desc = "Current symbols",
			prefix = "@",
			opts = { no_autoclose = true, fzf_opts = { ["--with-nth"] = false } },
		}
	elseif has_treesitter_symbols(bufnr) then
		pickers[#pickers + 1] = { "treesitter", desc = "Current symbols", prefix = "@" }
	end
	return pickers
end

local function global_picker_footer()
	local footer = " $ Open files"
	for _, picker in ipairs(global_picker_modes()) do
		if picker.prefix == "@" then
			footer = footer .. "  ·  @ Current symbols"
		end
	end
	return { { footer .. " ", "FzfLuaBorder" } }
end

local function open_buffers_command(opts)
	local utils = require("fzf-lua.utils")
	local path = require("fzf-lua.path")
	local context = utils.CTX()
	local cwd = opts.cwd or utils.cwd()
	local paths = {}
	local seen = {}
	for _, bufnr in ipairs(context and context.buflist or {}) do
		local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
		local stat = name ~= "" and vim.uv.fs_stat(name) or nil
		if stat and stat.type == "file" then
			name = path.relative_to(name, cwd)
			if not seen[name] then
				seen[name] = true
				paths[#paths + 1] = vim.fn.shellescape(name)
			end
		end
	end
	if #paths == 0 then
		return
	end
	return "printf '%s\\n' " .. table.concat(paths, " ")
end

local function register_smart_picker(fzf)
	fzf.smart = function(opts)
		opts = vim.deepcopy(opts or {})
		local start = opts._start
		local source_opts = vim.tbl_deep_extend("force", {}, opts, {
			_start = false,
			multiprocess = false,
			file_icons = false,
			color_icons = false,
		})
		local _, command, smart_opts = fzf.files(source_opts)
		assert(command and smart_opts, "smart picker file source is unavailable")
		local buffers = open_buffers_command(smart_opts)
		if buffers then
			command = string.format("{ %s; %s; } | awk '!seen[$0]++'", buffers, command)
		end
		smart_opts._start = start
		return require("fzf-lua.core").fzf_wrap(command, smart_opts)
	end
end

local function ensure_fzf(trigger)
	if fzf_setup_done then
		return require("fzf-lua")
	end
	if not lazy.packadd("fzf-lua", { notify = true, trigger = trigger or "picker" }) then
		return
	end

	local fzf = require("fzf-lua")
	register_smart_picker(fzf)
	local compat = require("mark.compat.fzf")
	compat.install_footer_headers()
	compat.install_preview_guards()
	local current_select = vim.ui.select
	local register_ui_select = current_select == select_fallback or (select_loader and current_select == select_loader)
	local setup_ok, setup_err = pcall(function()
		with_real_select(function()
			fzf.setup({
				ui_select = register_ui_select and {} or nil,
				winopts = {
					width = 0.95,
					height = 0.80,
					on_create = fzf_window.on_create(),
					preview = {
						flip_columns = 120,
						delay = 40,
					},
				},
				previewers = {
					builtin = {
						syntax_limit_b = 1024 * 512,
					},
				},
				buffers = {
					-- The current buffer is otherwise rendered as a non-selectable
					-- header, leaving nothing to navigate when only two buffers exist.
					fzf_opts = { ["--header-lines"] = false },
				},
				git = {
					files = {
						git_icons = false,
					},
				},
				grep = fzf_config.grep_options(),
				smart = {},
				global = {
					header = false,
					pickers = global_picker_modes,
					winopts = {
						title = " Smart Search ",
						title_flags = false,
						on_create = fzf_window.on_create(function(ctx)
							local config = vim.api.nvim_win_get_config(ctx.winid)
							if config.relative ~= "" then
								vim.api.nvim_win_set_config(ctx.winid, {
									footer = global_picker_footer(),
									footer_pos = "center",
								})
							end
						end),
					},
				},
			})
		end)
	end)
	if not setup_ok then
		if register_ui_select then
			vim.ui.select = current_select
		end
		error(setup_err, 0)
	end
	fzf_setup_done = true
	return fzf
end

local function picker(method, opts)
	return function()
		local fzf = ensure_fzf("picker keymap")
		if fzf then
			fzf[method](opts)
		end
	end
end

local function dap_picker(method)
	return function()
		if not require("mark.dap").ensure({ trigger = "fzf-lua DAP picker" }) then
			return
		end
		local fzf = ensure_fzf("DAP picker")
		if fzf then
			fzf[method]()
		end
	end
end

local picker_keymaps = {
	{ "n", "<C-M-o>", picker("global"), "Smart search" },
	{ { "n", "i" }, "<D-o>", picker("global"), "Smart search" },
	{ "n", "<leader>f/", picker("search_history"), "Search history" },
	{ "n", '<leader>f"', picker("registers"), "Search registers" },
	{ "n", "<leader>fB", picker("lines"), "Search open buffers" },
	{ "n", "<leader>fC", picker("colorschemes"), "Search colorschemes" },
	{ "n", "<leader>fG", picker("live_grep"), "Grep with glob filters" },
	{ "n", "<leader>fH", picker("highlights"), "Find highlights" },
	{ "n", "<leader>fL", picker("loclist"), "Search location list" },
	{ "n", "<leader>fR", picker("resume"), "Resume last picker" },
	{ "n", "<leader>fS", picker("lsp_workspace_symbols"), "LSP workspace symbols" },
	{ "n", "<leader>fa", picker("autocmds"), "Search autocmds" },
	{ "n", "<leader>fb", picker("buffers"), "Find buffer" },
	{ "n", "<leader>fc", picker("commands"), "Find commands" },
	{ "n", "<leader>fd", picker("diagnostics_workspace"), "Find diagnostics" },
	{ "n", "<leader>ff", picker("vcs_files"), "Find files" },
	{ "n", "<leader>fg", picker("global"), "Find files, buffers, and symbols" },
	{ "n", "<leader>fh", picker("helptags"), "Search help pages" },
	{ "n", "<leader>fj", picker("jumps"), "Search jumps" },
	{ "n", "<leader>fk", picker("keymaps"), "Search keymaps" },
	{ "n", "<leader>fl", picker("blines"), "Find line" },
	{ "n", "<leader>fm", picker("marks"), "Search marks" },
	{
		"n",
		"<leader>fn",
		function()
			vim.cmd("messages")
		end,
		"Message history",
	},
	{ "n", "<leader>fq", picker("quickfix"), "Search quickfix list" },
	{ "n", "<leader>fr", picker("history"), "Find recent files" },
	{ "n", "<leader>fs", picker("live_grep"), "Grep" },
	{ "n", "<leader>fu", picker("undotree"), "Search undo history" },
	{ "n", "<leader>fw", picker("grep_cword"), "Find word" },
	{ "x", "<leader>fw", picker("grep_visual"), "Find selection" },
	{ "n", "<leader>ls", picker("lsp_document_symbols"), "Document Symbols" },
	{ "n", "<leader>lS", picker("lsp_live_workspace_symbols"), "Workspace Symbols" },
	{ "n", "<leader>lr", picker("lsp_references"), "References" },
	{ "n", "<leader>gG", picker("git_status"), "Git Status" },
	{ "n", "<leader>gC", picker("git_commits"), "Git Commits" },
	{ "n", "<leader>gc", picker("git_bcommits"), "Current File Commits" },
	{ "n", "<leader>gA", picker("git_branches"), "Git Branches" },
	{ "n", "<leader>gW", picker("git_worktrees"), "Git Worktrees" },
	{ "n", "<leader>dC", dap_picker("dap_configurations"), "Debug Configurations" },
	{ "n", "<leader>dF", dap_picker("dap_frames"), "Debug Stack Frames" },
	{ "n", "<leader>dX", dap_picker("dap_breakpoints"), "Debug Breakpoints" },
}

for _, keymap in ipairs(picker_keymaps) do
	vim.keymap.set(keymap[1], keymap[2], keymap[3], { desc = keymap[4] })
end

local function installed_plugins()
	if not ensure_fzf("plugin picker") then
		return
	end
	require("mark.plugin_picker").open()
end

vim.api.nvim_create_user_command("InstalledPlugins", installed_plugins, {
	desc = "Browse installed plugins and their local configuration",
})

vim.api.nvim_create_autocmd("CmdUndefined", {
	pattern = "FzfLua",
	callback = function()
		ensure_fzf("CmdUndefined FzfLua")
	end,
	desc = "Lazy-load fzf-lua for :FzfLua",
})

vim.keymap.set("n", "<leader>fp", installed_plugins, {
	desc = "Find installed plugins",
})

select_loader = function(items, opts, on_choice)
	local current_select = vim.ui.select
	if current_select ~= select_loader then
		return current_select(items, opts, on_choice)
	end
	if select_loading then
		return call_select_fallback(items, opts, on_choice)
	end

	select_loading = true
	local ok, fzf = pcall(ensure_fzf, "vim.ui.select")
	select_loading = false
	if ok and fzf and vim.ui.select ~= select_loader then
		return vim.ui.select(items, opts, on_choice)
	end
	return call_select_fallback(items, opts, on_choice)
end

if vim.ui.select == select_fallback then
	vim.ui.select = select_loader
end
