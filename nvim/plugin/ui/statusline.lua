vim.g.qf_disable_statusline = 1 -- Don't show the command that produced the quickfix list
-- No %S item: this hides native showcmd, and plugin/ui/motion_echo.lua renders
-- pending keys instead (native %S would show mapping expansions such as "dd).
vim.o.showcmdloc = "statusline"

local statusline_escape_literal = require("mark.statusline.util").escape_literal
local symbols = icons.symbols
local git_icons = icons.git
local breadcrumb = require("mark.statusline.breadcrumbs").setup(symbols)

-- Initialize the _statusline table early for cache access
_G._statusline = _G._statusline or {}

local function remote_host()
	if vim.env.SSH_CONNECTION == nil or vim.env.SSH_CONNECTION == "" then
		return ""
	end

	local host = tostring(vim.fn.hostname() or ""):gsub("%c", " ")
	if host == "" then
		return ""
	end

	local max_width = 30
	if vim.fn.strdisplaywidth(host) > max_width then
		local chars = vim.fn.strchars(host)
		repeat
			chars = chars - 1
			host = vim.fn.strcharpart(host, 0, chars)
		until chars == 0 or vim.fn.strdisplaywidth(host .. ">") <= max_width
		host = host .. ">"
	end

	return "%#StatusLineRemote# @" .. statusline_escape_literal(host) .. "%#StatusLine#"
end

local modes = setmetatable({
	n = "NORMAL",
	no = "OP-PENDING",
	nov = "OP-PENDING",
	noV = "OP-PENDING",
	["no\22"] = "OP-PENDING",
	niI = "NORMAL",
	niR = "NORMAL",
	niV = "NORMAL",
	nt = "NORMAL",
	ntT = "NORMAL",
	v = "VISUAL",
	vs = "VISUAL",
	V = "VISUAL",
	Vs = "VISUAL",
	["\22"] = "VISUAL",
	["\22s"] = "VISUAL",
	s = "SELECT",
	S = "SELECT",
	["\19"] = "SELECT",
	i = "INSERT",
	ic = "INSERT",
	ix = "INSERT",
	R = "REPLACE",
	Rc = "REPLACE",
	Rx = "REPLACE",
	Rv = "VIRT REPLACE",
	Rvc = "VIRT REPLACE",
	Rvx = "VIRT REPLACE",
	c = "COMMAND",
	cv = "VIM EX",
	ce = "EX",
	r = "PROMPT",
	rm = "MORE",
	["r?"] = "CONFIRM",
	["!"] = "SHELL",
	t = "TERMINAL",
}, {
	__index = function(_, mode)
		-- Graceful fallback for unmapped modes: return uppercase mode string
		return mode:upper()
	end,
})

-- vim mode indicator with caching to avoid redundant highlight updates and string formatting
local mode_cache = { mode = nil, output = "" }

-- Mode highlight mapping (hoisted to module scope to avoid table allocation per redraw)
local mode_colors = {
	n = "StatusLineNormal",
	i = "StatusLineInsert",
	v = "StatusLineVisual",
	c = "StatusLineCommand",
	R = "StatusLineReplace",
	t = "StatusLineTerminal",
}

local function mode_color_key(current_mode)
	if current_mode:match("^no") or current_mode:match("^ni") or current_mode:match("^nt") then
		return "n"
	end
	if current_mode:match("^[vVsS\22\19]") then
		return "v"
	end
	if current_mode:match("^[r!c]") then
		return "c"
	end
	local key = current_mode:sub(1, 1)
	return mode_colors[key] and key or "n"
end

-- Pre-resolved fg color cache: canonical mode -> fg integer
-- Rebuilt on colorscheme change to pick up new palette
local mode_fg_cache = {}
local mode_text_fg_hex = "#000000"

local function apply_mode_highlights(current_mode)
	local fg = mode_fg_cache[mode_color_key(current_mode)]
	if not fg then
		return
	end
	vim.api.nvim_set_hl(0, "StatusLineModeLeft", { fg = fg, update = true })
	vim.api.nvim_set_hl(0, "StatusLineModeText", { bg = fg, update = true })
	vim.api.nvim_set_hl(0, "StatusLineModeRight", { fg = fg, update = true })
	vim.api.nvim_set_hl(0, "CursorLineNr", { fg = fg, update = true })
end

local function rebuild_mode_fg_cache()
	mode_cache.mode = nil -- force highlight rebuild on next render
	local configured_mode_fg = vim.api.nvim_get_hl(0, { name = "StatusLineModeText", link = false }).fg
	local normal_bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
	mode_text_fg_hex = string.format("#%06x", configured_mode_fg or normal_bg or 0x000000)
	for mode_char, hl_name in pairs(mode_colors) do
		mode_fg_cache[mode_char] = vim.api.nvim_get_hl(0, { name = hl_name }).fg
	end
	-- Set static mode highlight attributes (re-applied on colorscheme change).
	-- Dynamic mode color is merged via nvim_set_hl{update=true} in mode().
	vim.api.nvim_set_hl(0, "StatusLineModeLeft", { bg = "none", bold = true })
	vim.api.nvim_set_hl(0, "StatusLineModeRight", { bg = "none", bold = true })
	vim.api.nvim_set_hl(0, "StatusLineModeText", { fg = mode_text_fg_hex, bold = true })
	apply_mode_highlights(vim.api.nvim_get_mode().mode)
end

-- Build initial cache synchronously (must run before first render).
-- ColorScheme autocmd for runtime changes is in the deferred vim.schedule block.
rebuild_mode_fg_cache()

local function mode()
	local current_mode = vim.api.nvim_get_mode().mode

	-- Only update highlights and formatted output when mode actually changes
	if mode_cache.mode ~= current_mode then
		mode_cache.mode = current_mode
		apply_mode_highlights(current_mode)

		mode_cache.output = string.format(
			"%%#StatusLineModeLeft#%s%%#StatusLineModeText#%s%%#StatusLineModeRight#%s%%#StatusLine#",
			symbols.left,
			modes[current_mode],
			symbols.right
		)
	end

	return mode_cache.output
end

-- buffer status indicators (pre-allocated parts table to avoid GC pressure)
local _buf_status_parts = {}
local function buf_status()
	local n = 0

	if vim.bo.modified then
		n = n + 1
		_buf_status_parts[n] = symbols.modified
	end

	if vim.bo.readonly then
		n = n + 1
		_buf_status_parts[n] = symbols.readonly
	end

	if vim.api.nvim_buf_get_name(0) == "" then
		local icons = package.loaded["mini.icons"]
		n = n + 1
		_buf_status_parts[n] = icons and icons.get("file", "") or symbols.unnamed
	end

	if n > 0 then
		return string.format(" %%#Special#%s %%#StatusLine#", table.concat(_buf_status_parts, " ", 1, n))
	end

	return " "
end

-- filetype icon
local function filetype()
	local ft = vim.bo.filetype

	-- Only use mini.icons if loaded (checked via package.loaded for zero-cost lookup)
	local icons = package.loaded["mini.icons"]
	if icons then
		return string.format("%%#Special#%s %%#StatusLine#", icons.get("filetype", ft))
	end

	-- Placeholder when mini.icons not loaded
	return " "
end

-- git status (pre-allocated parts table to avoid GC pressure)
local _git_parts = {}
local function git()
	local status = vim.b.minidiff_summary

	if not status then
		return ""
	end

	local n = 0

	if status.add and status.add > 0 then
		n = n + 1
		_git_parts[n] = string.format("%%#GitStatusAdded#%s%s%%*", git_icons.added, status.add)
	end

	if status.change and status.change > 0 then
		n = n + 1
		_git_parts[n] = string.format("%%#GitStatusChanged#%s%s%%*", git_icons.modified, status.change)
	end

	if status.delete and status.delete > 0 then
		n = n + 1
		_git_parts[n] = string.format("%%#GitStatusRemoved#%s%s%%*", git_icons.removed, status.delete)
	end

	return n > 0 and table.concat(_git_parts, " ", 1, n) .. " " or ""
end

-- modified buffer indicator with caching
local modified_bufs_cache = { value = "", dirty = true, current_bufnr = nil }
local modified_state = {}

-- Diagnostic cache: scoped per buffer and recomputed only when that buffer's diagnostics change.
local _diag_cache = {}
local _last_valid_statusline = ""

-- Deferred event autocmds (registered here because they reference locals defined
-- after the first vim.schedule block: rebuild_mode_fg_cache, modified_bufs_cache, _diag_cache)
vim.schedule(function()
	local events_group = vim.api.nvim_create_augroup("statusline_events")
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = events_group,
		callback = rebuild_mode_fg_cache,
		desc = "Rebuild statusline mode fg cache on colorscheme change",
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = events_group,
		callback = function(ev)
			mode_cache.mode = nil
			local next_mode = ev.match:match(":(.+)$") or vim.api.nvim_get_mode().mode
			apply_mode_highlights(next_mode)
		end,
		desc = "Match the current line number to the statusline mode color",
	})
	local function invalidate_modified_buffers_cache(ev)
		if ev and ev.buf then
			modified_state[ev.buf] = vim.bo[ev.buf].modified
		end
		modified_bufs_cache.dirty = true
	end
	vim.api.nvim_create_autocmd({ "BufWritePost", "BufDelete", "BufWipeout", "BufUnload", "BufAdd" }, {
		group = events_group,
		callback = invalidate_modified_buffers_cache,
		desc = "Invalidate modified buffers cache",
	})
	-- OptionSet is the 0.13 replacement for the removed BufModifiedSet event.
	-- Keep this fallback for internally driven modified-state transitions; it
	-- dirties the cache only when the observed state changes, not on every edit.
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = events_group,
		callback = function(ev)
			local modified = vim.bo[ev.buf].modified
			if modified_state[ev.buf] ~= modified then
				modified_state[ev.buf] = modified
				modified_bufs_cache.dirty = true
			end
		end,
		desc = "Invalidate modified buffers cache on observed modified transitions",
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		group = events_group,
		pattern = "modified",
		callback = invalidate_modified_buffers_cache,
		desc = "Invalidate modified buffers cache on modified option changes",
	})
	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = events_group,
		callback = function(ev)
			local cache = _diag_cache[ev.buf]
			if cache then
				cache.dirty = true
			end
		end,
		desc = "Invalidate diagnostic cache for changed buffer",
	})
	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = events_group,
		callback = function(ev)
			_diag_cache[ev.buf] = nil
			modified_state[ev.buf] = nil
		end,
		desc = "Discard per-buffer statusline caches for deleted buffers",
	})
	vim.api.nvim_create_autocmd({ "TabEnter", "TabNew", "TabClosed", "TabMoved" }, {
		group = events_group,
		callback = function()
			vim.cmd.redrawstatus()
		end,
		desc = "Redraw statusline tab indicators",
	})
	vim.api.nvim_create_autocmd("User", {
		group = events_group,
		pattern = "DapProgressUpdate",
		callback = function()
			vim.cmd.redrawstatus()
		end,
		desc = "Redraw statusline debugger status",
	})
end)

local function modified_buffers()
	local current_bufnr = vim.api.nvim_get_current_buf()
	if not modified_bufs_cache.dirty and modified_bufs_cache.current_bufnr == current_bufnr then
		return modified_bufs_cache.value
	end

	local out = ""

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if
			bufnr ~= current_bufnr
			and vim.api.nvim_buf_is_loaded(bufnr)
			and vim.bo[bufnr].buflisted
			and vim.bo[bufnr].modified
		then
			out = out .. symbols.modified .. " "
		end
	end

	local result = out ~= "" and "%#StatusLineModifiedBuffer#" .. out .. " " or ""
	modified_bufs_cache.dirty = false
	modified_bufs_cache.current_bufnr = current_bufnr
	modified_bufs_cache.value = result
	return result
end

local function dap()
	if not package.loaded["dap"] then
		return ""
	end
	local status = require("dap").status()
	if status == "" then
		return ""
	end

	return "%#StatusLineDebug# " .. icons.dap.Session .. statusline_escape_literal(status) .. " "
end

local function recording()
	local reg = vim.fn.reg_recording()
	if reg ~= "" then
		return "%#StatusLineMotion#recording@ " .. reg .. " "
	end
	return ""
end

-- open tab indicators
local function tabs()
	local tab_list = vim.api.nvim_list_tabpages()
	if #tab_list <= 1 then
		return ""
	end

	local current = vim.api.nvim_get_current_tabpage()
	local parts = {}
	for i, tabpage in ipairs(tab_list) do
		if tabpage == current then
			parts[#parts + 1] = "%#Special#" .. i .. "%#Normal# "
		else
			parts[#parts + 1] = i .. " "
		end
	end
	return table.concat(parts) .. " "
end

_G._statusline.recording = recording

function _G._statusline.motion_echo()
	return _G._motion_echo and _G._motion_echo.get() or ""
end

-- Pre-allocated render table (reused every render to avoid GC pressure)
local _render_parts = {}
-- Pre-built static suffix (never changes, built once)
local _render_suffix = "%#StatusLineBufferPercentageSymbol#"
	.. symbols.left
	.. "%#StatusLineBufferPercentage#%2P %#StatusLineBufferPosition# %3l:%-3c%#StatusLineBufferPositionSymbol#"
	.. symbols.right

function _G._statusline.render()
	-- Hide statusline for ui2 special buffers (cmd, dialog, msg, pager)
	local ft = vim.bo.filetype
	if ft == "cmd" or ft == "dialog" or ft == "msg" or ft == "pager" then
		return _last_valid_statusline
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local fname = vim.api.nvim_buf_get_name(bufnr)
	local root = breadcrumb.project_root(bufnr, fname, vim.fn.getcwd(0, 0))
	local diag_cache = _diag_cache[bufnr]
	if not diag_cache then
		diag_cache = { value = "", dirty = true }
		_diag_cache[bufnr] = diag_cache
	end
	if diag_cache.dirty then
		local diagnostic = package.loaded["vim.diagnostic"]
		diag_cache.value = diagnostic and diagnostic.status(bufnr) or ""
		diag_cache.dirty = false
	end

	local parts = _render_parts
	local diag = diag_cache.value

	parts[1] = mode()
	parts[2] = remote_host() .. " "
	parts[3] = diag
	parts[4] = diag ~= "" and symbols.separator or ""
	parts[5] = root.value
	parts[6] = filetype()
	parts[7] = breadcrumb.render(root.path_base, fname)
	parts[8] = buf_status()
	parts[9] = "%#StatusLine#%="
	parts[10] = dap()
	-- %{} (not %{%%}) keeps typed keys such as `%` literal.
	parts[11] = "%#StatusLineMotion#%{v:lua._statusline.motion_echo()} "
	parts[12] = "%{%v:lua._statusline.recording()%}"
	parts[13] = git()
	parts[14] = modified_buffers()
	parts[15] = tabs()
	parts[16] = _render_suffix

	local result = table.concat(parts, "", 1, 16)
	_last_valid_statusline = result
	return result
end

local _sl_value = "%!v:lua._statusline.render()"
local _sl_group = vim.api.nvim_create_augroup("statusline_activate")

-- Install the expression before startup reads file arguments. Waiting for
-- BufReadPost lets Neovim's default %f briefly render the unshortened path.
vim.o.statusline = _sl_value

local function activate_visible_statusline()
	vim.o.statusline = _sl_value
	vim.o.laststatus = 3
end

vim.api.nvim_create_autocmd("BufReadPost", {
	group = _sl_group,
	once = true,
	callback = activate_visible_statusline,
})

vim.api.nvim_create_autocmd("SessionLoadPost", {
	group = _sl_group,
	callback = activate_visible_statusline,
})

-- Final override: ensure custom statusline survives any deferred startup overrides
-- (e.g., Neovim nightly setting the built-in default after plugin loading)
vim.api.nvim_create_autocmd("VimEnter", {
	group = _sl_group,
	once = true,
	callback = function()
		vim.schedule(function()
			vim.o.statusline = _sl_value
		end)
	end,
})
