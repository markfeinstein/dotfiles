-- Delay before closing folds to ensure treesitter has created them
local FOLD_WAIT_MS = 200
local bigfile = require("mark.bigfile")
local lazy = require("mark.lazy")
local treesitter = require("mark.treesitter")

local function save_callout_fold_state(winid, state)
	vim.w[winid].callouts_fold_state = state
end

local function callout_fold_state(winid)
	local state = vim.w[winid].callouts_fold_state
	local changed = false
	if not state then
		state = { done = {}, pending = {} }
		changed = true
	end
	if not state.done then
		state.done = {}
		changed = true
	end
	if not state.pending then
		state.pending = {}
		changed = true
	end
	if changed then
		save_callout_fold_state(winid, state)
	end
	return state
end

local function callout_quote_end(lines, start)
	local end_line = start
	while end_line < #lines and lines[end_line + 1]:match("^>") do
		end_line = end_line + 1
	end
	return end_line
end

local function computed_fold_end(start, level, line_count)
	local end_line = start
	for lnum = start + 1, line_count do
		if vim.fn.foldlevel(lnum) < level then
			return end_line
		end
		end_line = lnum
	end
	return end_line
end

local function has_block_quote_fold_capture(bufnr, start_line, end_line)
	local query_ok, query = pcall(vim.treesitter.query.get, "markdown", "folds")
	if not query_ok or not query then
		return false
	end

	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
	if not parser_ok or not parser then
		return false
	end

	local trees_ok, trees = pcall(parser.parse, parser)
	if not trees_ok or type(trees) ~= "table" then
		return false
	end

	for _, tree in ipairs(trees) do
		local root = tree:root()
		for id, node in query:iter_captures(root, bufnr, start_line - 1, end_line) do
			local name = query.captures[id]
			if name == "fold" and node:type() == "block_quote" then
				local start_row, _, end_row, end_col = node:range()
				local last_line = end_row + (end_col > 0 and 1 or 0)
				if start_row == start_line - 1 and last_line == end_line then
					return true
				end
			end
		end
	end
	return false
end

-- Helper function to close Tree-sitter-computed folds for Obsidian collapsible callouts.
-- Detects callouts with `-` syntax (e.g., > [!NOTE]-) without creating manual folds.
local function close_collapsible_callouts(bufnr, winid)
	if bigfile.is_guarded(bufnr) then
		return
	end

	local state = callout_fold_state(winid)
	local bufkey = tostring(bufnr)
	local token = vim.uv.hrtime()
	state.pending[bufkey] = token
	save_callout_fold_state(winid, state)

	-- Use defer_fn with delay to ensure treesitter has computed folds.
	vim.defer_fn(function()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		if not vim.api.nvim_win_is_valid(winid) then
			return
		end

		local current_state = callout_fold_state(winid)
		if current_state.pending[bufkey] ~= token then
			return
		end
		if bigfile.is_guarded(bufnr) then
			current_state.pending[bufkey] = nil
			save_callout_fold_state(winid, current_state)
			return
		end
		if vim.api.nvim_win_get_buf(winid) ~= bufnr then
			current_state.pending[bufkey] = nil
			save_callout_fold_state(winid, current_state)
			return
		end

		vim.api.nvim_win_call(winid, function()
			local view = vim.fn.winsaveview()
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local has_incomplete = false
			local foldexpr = vim.wo[winid].foldexpr
			local use_treesitter_folds = vim.wo[winid].foldenable
				and vim.wo[winid].foldmethod == "expr"
				and (
					foldexpr == vim.treesitter.foldexpr
					or (foldexpr == treesitter.foldexpr and treesitter.folds_enabled(bufnr))
					or (type(foldexpr) == "string" and foldexpr:find("treesitter", 1, true))
				)

			for i, line in ipairs(lines) do
				-- Match Obsidian collapsible callout syntax: >[!TYPE]- or > [!TYPE]-
				if line:match("^>%s*%[![^%]]+%]%-") then
					local quote_end = callout_quote_end(lines, i)
					if quote_end > i then
						local previous_level = i > 1 and vim.fn.foldlevel(i - 1) or 0
						local current_level = vim.fn.foldlevel(i)
						local fold_starts_here = use_treesitter_folds and current_level > previous_level
						local fold_ends_here = fold_starts_here
							and computed_fold_end(i, current_level, #lines) == quote_end
						local has_callout_fold_capture = fold_ends_here
							and has_block_quote_fold_capture(bufnr, i, quote_end)

						if not use_treesitter_folds or not fold_ends_here or not has_callout_fold_capture then
							has_incomplete = true
						elseif vim.fn.foldclosed(i) == i and vim.fn.foldclosedend(i) == quote_end then
							-- Already closed to the matching callout fold.
						elseif vim.fn.foldclosed(i) == -1 then
							local cursor_ok = pcall(vim.api.nvim_win_set_cursor, winid, { i, 0 })
							local close_ok = cursor_ok and pcall(vim.cmd, "normal! zc")
							if close_ok and (vim.fn.foldclosed(i) ~= i or vim.fn.foldclosedend(i) ~= quote_end) then
								pcall(vim.cmd, "normal! zo")
							end
							if not close_ok or vim.fn.foldclosed(i) ~= i or vim.fn.foldclosedend(i) ~= quote_end then
								has_incomplete = true
							end
						else
							has_incomplete = true
						end
					end
				end
			end

			vim.fn.winrestview(view)
			current_state.done[bufkey] = not has_incomplete
			current_state.pending[bufkey] = nil
			save_callout_fold_state(winid, current_state)
		end)
	end, FOLD_WAIT_MS)
end

-- Vault paths are supplied by the active Nix profile. The common work profile
-- intentionally remains dormant until its private repository adds workspaces.
local vault_workspaces = {}
local vault_patterns = {}
for _, workspace in ipairs(vim.g.dotfiles_obsidian_workspaces or {}) do
	local path = vim.fn.expand(workspace.path)
	vault_workspaces[#vault_workspaces + 1] = { name = workspace.name, path = path }
	vault_patterns[#vault_patterns + 1] = vim.fs.joinpath(path, "*.md")
	vault_patterns[#vault_patterns + 1] = vim.fs.joinpath(path, "**", "*.md")
end

-- Defer vault configuration loading until plugin opts are evaluated
-- This wraps the config in a function that only runs when obsidian.nvim loads
local function get_obsidian_config()
	return {
		legacy_commands = false,
		workspaces = vault_workspaces,
		daily_notes = {
			folder = "Journal/Daily",
			date_format = "%Y-%m-%d",
			alias_format = "%B %-d, %Y",
			template = "Daily Note.md",
		},
		completion = {
			min_chars = 1,
			match_case = false,
		},
		notes_subdir = "Inbox",

		note_id_func = function(title)
			return title
		end,
		templates = {
			folder = "Resources/Templates",
		},
		checkbox = {
			order = {
				" ", -- [ ] unchecked
				"~", -- 󰜎 in-progress
				"x", -- [x] done
				"!", -- 󰀪 important
				"-", --  cancelled
				">", -- 󰸗 forwarded
			},
		},
		ui = { enable = false },
		-- picker: auto-detected; fzf-lua is packadded before obsidian.nvim loads.
		footer = {
			format = "{{links}} links  {{backlinks}} backlinks  {{properties}} properties  {{words}} words  {{chars}} chars",
		},
	}
end

local function has_completed_obsidian_client()
	if package.loaded["obsidian"] == nil then
		return false
	end

	local ok, obsidian = pcall(require, "obsidian")
	if not ok or type(obsidian.get_client) ~= "function" then
		return false
	end

	local client_ok, client = pcall(obsidian.get_client)
	return client_ok and client ~= nil
end

local obsidian_is_setup = has_completed_obsidian_client()

local function ensure_obsidian_loaded(trigger)
	if #vault_workspaces == 0 then
		vim.notify("No Obsidian workspaces are configured for this profile", vim.log.levels.INFO)
		return false
	end

	if not package.loaded["obsidian"] then
		local pack_opts = { notify = true, trigger = trigger or "unknown" }
		if not lazy.packadd("fzf-lua", pack_opts) or not lazy.packadd("obsidian.nvim", pack_opts) then
			return false
		end
	end

	if obsidian_is_setup then
		return true
	end

	local obsidian = lazy.require("obsidian", { notify = true })
	if not obsidian then
		return false
	end

	obsidian.setup(get_obsidian_config())
	obsidian_is_setup = true
	return true
end

-- Proxy command: auto-loads obsidian plugin on first :Obsidian use at startup.
-- setup() registers the real :Obsidian command, replacing this proxy. Keep the
-- proxy command shape aligned with obsidian.nvim's command (nargs=*, range=2)
-- so structured redispatch preserves the original invocation contract.
if package.loaded["obsidian"] == nil then
	vim.api.nvim_create_user_command("Obsidian", function(opts)
		pcall(vim.api.nvim_del_user_command, "Obsidian")
		if ensure_obsidian_loaded(":Obsidian") then
			local command = {
				cmd = "Obsidian",
				args = opts.fargs,
				mods = opts.smods,
				magic = { bar = false, file = false },
			}
			if opts.range == 1 then
				command.range = { opts.line1 }
			elseif opts.range == 2 then
				command.range = { opts.line1, opts.line2 }
			end
			vim.api.nvim_cmd(command)
		else
			vim.notify("Failed to load obsidian.nvim", vim.log.levels.ERROR)
		end
	end, { nargs = "*", range = 2 })
end

-- Obsidian vault autocmds deferred to avoid startup cost (obsidian is lazy-loaded).
-- Hoisted navigation helpers avoid closure re-allocation on every BufEnter.
local function _get_daily_date(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	local year, month, day = path:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if year and month and day then
		return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day) })
	end
	return nil
end

local function _navigate_daily(bufnr, offset_days)
	local base_time = _get_daily_date(bufnr) or os.time()
	local target_time = base_time + (offset_days * 24 * 60 * 60)
	-- Prefer the plugin API when navigating relative to the current daily note.
	local ok = pcall(function()
		require("obsidian.daily").daily({ date = target_time }):open()
	end)
	if not ok then
		-- Fall back to the public command interface if the internal API changes.
		vim.cmd("Obsidian daily " .. tostring(offset_days))
	end
end

if #vault_patterns > 0 then
	local obsidian_group = vim.api.nvim_create_augroup("obsidian_vault")

	vim.api.nvim_create_autocmd("BufReadPre", {
		group = obsidian_group,
		pattern = vault_patterns,
		callback = function()
			ensure_obsidian_loaded("BufReadPre")
		end,
		desc = "Load Obsidian for vault files",
	})

	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = obsidian_group,
		pattern = vault_patterns,
		callback = function(ev)
			if bigfile.is_guarded(ev.buf) then
				return
			end

			local winid = vim.api.nvim_get_current_win()
			local bufkey = tostring(ev.buf)
			local state = callout_fold_state(winid)
			if state.done[bufkey] or state.pending[bufkey] then
				return
			end
			if package.loaded["obsidian"] then
				close_collapsible_callouts(ev.buf, winid)
			end
		end,
		desc = "Auto-fold Obsidian collapsible callouts",
	})

	vim.api.nvim_create_autocmd("BufLeave", {
		group = obsidian_group,
		pattern = vault_patterns,
		callback = function(ev)
			if package.loaded["obsidian"] and vim.bo[ev.buf].modified then
				vim.cmd("silent! write")
			end
		end,
		desc = "Auto-save Obsidian notes when leaving buffer",
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = obsidian_group,
		pattern = vault_patterns,
		callback = function(ev)
			if not package.loaded["obsidian"] then
				return
			end
			local bufnr = ev.buf
			if vim.b[bufnr]._obsidian_nav_set then
				return
			end
			vim.b[bufnr]._obsidian_nav_set = true
			vim.keymap.set("n", "[d", function()
				_navigate_daily(bufnr, -1)
			end, { buf = bufnr, desc = "Previous Daily Note" })
			vim.keymap.set("n", "]d", function()
				_navigate_daily(bufnr, 1)
			end, { buf = bufnr, desc = "Next Daily Note" })
			vim.keymap.set("n", "<C-M-o>", "<cmd>Obsidian search<cr>", { buf = bufnr, desc = "Search Notes" })
		end,
		desc = "Setup Obsidian daily navigation keybinds",
	})
end
