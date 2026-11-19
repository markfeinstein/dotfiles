-- Weekly/monthly/quarterly/yearly notes for obsidian.nvim, configured with the
-- same settings object as the Obsidian desktop Periodic Notes plugin so both
-- editors create identical paths from identical templates.
local M = {}
local intervals = { "daily", "weekly", "monthly", "quarterly", "yearly" }

local function parse_date(value)
	if value == nil then
		return os.time()
	end
	local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	assert(year, "Date must be YYYY-MM-DD")
	local timestamp = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
	assert(timestamp and os.date("%Y-%m-%d", timestamp) == value, "Invalid calendar date: " .. value)
	return timestamp
end

local function period_start(interval, timestamp)
	local date = os.date("*t", timestamp)
	date.hour, date.min, date.sec = 12, 0, 0
	if interval == "weekly" then
		date.day = date.day - (date.wday + 5) % 7 -- ISO Monday, including across DST/year boundaries.
	elseif interval == "monthly" then
		date.day = 1
	elseif interval == "quarterly" then
		date.month, date.day = math.floor((date.month - 1) / 3) * 3 + 1, 1
	elseif interval == "yearly" then
		date.month, date.day = 1, 1
	end
	date.isdst = nil
	return assert(os.time(date))
end

-- Validate every existing component, including the final file. Never write
-- through a symlink or allow configuration to escape the selected vault.
local function vault_path(root, relative)
	assert(relative ~= "" and not relative:match("^[/~]") and not relative:find("\\", 1, true),
		"Expected a vault-relative path")
	local path = root
	for part in relative:gmatch("[^/]+") do
		assert(part ~= ".." and part ~= "." and part ~= ".obsidian" and part ~= ".trash", "Unsafe vault path")
		path = path .. "/" .. part
		local stat = vim.uv.fs_lstat(path)
		assert(not stat or stat.type == "directory" or stat.type == "file", "Unsupported path component: " .. path)
	end
	return path
end

-- Exact name lookup; bufnr() would treat the path as a pattern.
local function buffer_for_path(path)
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(buffer) == path then
			return buffer
		end
	end
end

local function workspace_for_buffer()
	local workspaces = (vim.g.dotfiles_obsidian or {}).workspaces or {}
	local current = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
	local selected
	for _, workspace in ipairs(workspaces) do
		local root = vim.fs.normalize(vim.fn.expand(workspace.path)):gsub("/+$", "")
		if current == root or vim.startswith(current, root .. "/") then
			if not selected or #root > #selected.path then
				selected = { name = workspace.name, path = root }
			end
		end
	end
	selected = selected or workspaces[1]
	assert(selected, "No Obsidian workspaces configured")
	local root = vim.fs.normalize(vim.fn.expand(selected.path)):gsub("/+$", "")
	assert(vim.uv.fs_realpath(root) == root, "Vault must be an existing canonical directory, not a symlink")
	return { name = selected.name, path = root }
end

local function daily_period(note)
	local value = tostring(note.id):match("^(%d%d%d%d%-%d%d%-%d%d)")
	if not value then return end
	local ok, timestamp = pcall(parse_date, value)
	if not ok then return end
	local daily = M.settings.daily
	local filename = require("obsidian.date").format(timestamp, daily.format, 1)
	for _, workspace in ipairs((vim.g.dotfiles_obsidian or {}).workspaces or {}) do
		local expected = vim.fs.joinpath(vim.fn.expand(workspace.path), daily.folder, filename .. ".md")
		if tostring(note.path) == expected then
			return { timestamp = timestamp, format = daily.format }
		end
	end
end

-- The real obsidian.nvim renderer passes partial_note to substitutions. Carry
-- the note's period explicitly instead of temporarily changing global date/time
-- or mutating ordinary notes' rendering. Preserve the original substitution.
local function period_substitutions()
	local substitutions = Obsidian.opts.templates.substitutions
	local original = substitutions.date
	if original == M.date_substitution then
		return
	end
	M.date_substitution = function(ctx, suffix)
		local note = ctx.partial_note
		local period = note and (note.dotfiles_period or daily_period(note))
		if period then
			return require("obsidian.date").format(period.timestamp, suffix or period.format, 1)
		end
		return type(original) == "function" and original(ctx, suffix) or original
	end
	substitutions.date = M.date_substitution
end

function M.open(settings, interval, value)
	assert(vim.tbl_contains(intervals, interval), "Interval must be daily, weekly, monthly, quarterly or yearly")
	local config = assert(settings[interval], "Missing interval settings")
	assert(config.enabled, "Interval is disabled: " .. interval)
	local timestamp = period_start(interval, parse_date(value))
	local workspace = workspace_for_buffer()
	-- Dispatch through the shared profile's real lazy-loading proxy. Structured
	-- arguments avoid command injection and select the containing workspace.
	vim.api.nvim_cmd({ cmd = "Obsidian", args = { "workspace", workspace.name } }, {})
	assert(package.loaded.obsidian and _G.Obsidian, "Unable to load obsidian.nvim")
	local filename = require("obsidian.date").format(timestamp, config.format, 1)
	local path = vault_path(workspace.path, config.folder .. "/" .. filename .. ".md")
	local template = vault_path(workspace.path, config.template .. ".md")

	-- Existing files and loaded (even unsaved) buffers are authoritative. Opening
	-- an existing period must not reapply a template or save unrelated edits.
	-- Switch to an existing buffer directly: `:edit` on a modified current buffer
	-- would prompt to save (or reload) under 'confirm'/'autowrite'.
	local existing = buffer_for_path(path)
	if existing then
		if existing ~= vim.api.nvim_get_current_buf() then
			vim.api.nvim_set_current_buf(existing)
		end
		return path
	end
	if vim.uv.fs_stat(path) then
		vim.api.nvim_cmd({ cmd = "edit", args = { path } }, {})
		return path
	end
	assert(vim.fn.filereadable(template) == 1, "Missing periodic template: " .. template)
	assert(not vim.bo.modified or vim.o.hidden, "Save the current buffer before opening a periodic note")
	period_substitutions()
	local note = require("obsidian.note").create({
		id = vim.fs.basename(path):gsub("%.md$", ""),
		title = vim.fs.basename(path):gsub("%.md$", ""),
		dir = vim.fs.dirname(path),
		verbatim = true,
		template = template,
		scope = "periodic",
	})
	note.dotfiles_period = { timestamp = timestamp, format = config.format }
	note = note:write({})
	note:open()
	return path
end

function M.setup(opts)
	opts = opts or {}
	local settings = opts.settings
	M.settings = settings
	if not opts.enabled or type(settings) ~= "table" then
		return
	end
	local profile = vim.g.dotfiles_obsidian or {}
	if #(profile.workspaces or {}) == 0 then
		return
	end
	-- This also covers native :Obsidian daily, navigation, and log capture, so
	-- historical daily templates use the note's date rather than today's date.
	vim.api.nvim_create_autocmd("User", {
		group = vim.api.nvim_create_augroup("dotfiles_obsidian_periodic_templates", { clear = true }),
		pattern = "ObsidianNoteCreate",
		callback = period_substitutions,
	})
	local function run(interval, value)
		local ok, err = pcall(M.open, settings, interval, value)
		if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
	end
	vim.api.nvim_create_user_command("ObsidianPeriodic", function(opts)
		if #opts.fargs < 1 or #opts.fargs > 2 then
			vim.notify("Usage: ObsidianPeriodic <interval> [YYYY-MM-DD]", vim.log.levels.ERROR)
			return
		end
		run(opts.fargs[1], opts.fargs[2])
	end, {
		nargs = "+",
		complete = function(prefix)
			return vim.tbl_filter(function(interval) return vim.startswith(interval, prefix) end, intervals)
		end,
		desc = "Open/create a periodic note using the Periodic Notes settings",
	})
	for _, interval in ipairs({ "weekly", "monthly", "quarterly", "yearly" }) do
		vim.api.nvim_create_user_command("Obsidian" .. interval:gsub("^%l", string.upper), function(opts)
			run(interval, opts.args ~= "" and opts.args or nil)
		end, { nargs = "?", desc = "Open/create the " .. interval .. " note [YYYY-MM-DD]" })
	end
end

return M
