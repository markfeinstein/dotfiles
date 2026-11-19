-- Runs after a normal startup of the packaged config with two temporary vaults
-- and periodic notes enabled. Creates notes only inside those vaults.
local function equal(expected, actual, label)
	assert(
		vim.deep_equal(expected, actual),
		label .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
	)
end

local function check()
	local profile = vim.g.dotfiles_obsidian
	local settings = assert(profile.periodic and profile.periodic.settings, "generated periodic settings")
	equal(true, profile.periodic.enabled, "generated periodic flag")
	equal(settings.daily.folder, profile.daily_notes.folder, "generated daily folder matches periodic settings")
	local tokens = { Y = "YYYY", m = "MM", B = "MMMM", d = "DD", A = "dddd" }
	equal(settings.daily.format, (profile.daily_notes.date_format:gsub("%%([YmBdA])", tokens)), "daily format")
	equal(profile.templates.folder .. "/Daily Note", settings.daily.template, "daily template")

	local vault = assert(vim.uv.fs_realpath(vim.fn.expand(profile.workspaces[1].path)))
	local second = assert(vim.uv.fs_realpath(vim.fn.expand(profile.workspaces[2].path)))
	for _, path in ipairs({ vault, second }) do
		vim.fn.mkdir(path .. "/" .. profile.templates.folder, "p")
		for interval, entry in pairs(settings) do
			if type(entry) == "table" then
				vim.fn.writefile({
					"---",
					"type: " .. interval,
					'date: "{{date:YYYY-MM-DD}}"',
					"---",
					"# {{title}}",
					"Period: {{date}}",
					"Marker: " .. interval,
				}, path .. "/" .. entry.template .. ".md")
			end
		end
	end
	vim.o.hidden = true
	local notifications = {}
	vim.notify = function(message, level)
		notifications[#notifications + 1] = { message, level }
	end

	for _, command in ipairs({ "Periodic", "Weekly", "Monthly", "Quarterly", "Yearly" }) do
		equal(2, vim.fn.exists(":Obsidian" .. command), "command registered: " .. command)
	end
	assert(not package.loaded.obsidian, "commands preserve lazy loading")
	vim.cmd("ObsidianMonthly 2027-02-30")
	assert(not package.loaded.obsidian, "invalid dates do not load the plugin or create a note")
	equal(vim.log.levels.ERROR, notifications[#notifications][2], "invalid date reported")

	local periodic = require("mark.obsidian_periodic")
	local cases = {
		{ "daily", "2027-01-01", "2027/01-January/2027-01-01-Friday", "2027-01-01" },
		{ "weekly", "2027-01-01", "2026-W53", "2026-12-28" },
		{ "weekly", "2027-01-03", "2026-W53", "2026-12-28" },
		{ "weekly", "2027-01-04", "2027-W01", "2027-01-04" },
		{ "monthly", "2027-01-31", "2027-01", "2027-01-01" },
		{ "quarterly", "2026-12-31", "2026-Q4", "2026-10-01" },
		{ "quarterly", "2027-01-01", "2027-Q1", "2027-01-01" },
		{ "yearly", "2027-12-31", "2027", "2027-01-01" },
		{ "daily", "2028-02-29", "2028/02-February/2028-02-29-Tuesday", "2028-02-29" },
		{ "weekly", "2027-03-14", "2027-W10", "2027-03-08" },
		{ "weekly", "2027-11-07", "2027-W44", "2027-11-01" },
	}
	for _, case in ipairs(cases) do
		local interval, date, filename, period_date = unpack(case)
		vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
		local path = periodic.open(settings, interval, date)
		equal(vault .. "/" .. settings[interval].folder .. "/" .. filename .. ".md", path, interval .. " path: " .. date)
		assert(
			vim.wait(2000, function()
				return vim.api.nvim_buf_get_name(0) == path
			end),
			"real note opened"
		)
		local text = table.concat(vim.fn.readfile(path), "\n")
		equal(period_date, require("obsidian.note").from_file(path).metadata.date, "template receives period date")
		assert(text:find("Marker: " .. interval, 1, true), "correct interval template applied")
		assert(not text:find("{{", 1, true), "no unresolved template tokens")
	end

	-- The user commands use the containing workspace, not the first.
	vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
	vim.api.nvim_buf_set_name(0, second .. "/source.md")
	vim.cmd("ObsidianMonthly 2027-05-20")
	local path = second .. "/" .. settings.monthly.folder .. "/2027-05.md"
	assert(
		vim.wait(2000, function()
			return vim.api.nvim_buf_get_name(0) == path
		end),
		"command selects second workspace"
	)
	local disk = vim.fn.readfile(path)
	vim.api.nvim_buf_set_lines(0, -1, -1, false, { "Unsaved history" })
	local buffer = vim.api.nvim_get_current_buf()
	vim.cmd("ObsidianMonthly 2027-05-01")
	equal(buffer, vim.api.nvim_get_current_buf(), "existing buffer reopened")
	assert(vim.bo.modified, "existing unsaved edits remain unsaved")
	equal("Unsaved history", vim.api.nvim_buf_get_lines(0, -2, -1, false)[1], "existing buffer not templated")
	equal(disk, vim.fn.readfile(path), "existing file not overwritten or saved")

	-- Native obsidian.nvim daily creation gets the historical date hook too.
	local note = require("obsidian.daily").daily({ date = os.time({ year = 2000, month = 1, day = 1, hour = 12 }), dir = second })
	note:write({})
	equal("2000-01-01", require("obsidian.note").from_file(note.path).metadata.date, "native historical daily template date")

	local ordinary = require("obsidian.note").new("ordinary", {}, {}, second .. "/ordinary.md", "ordinary")
	equal(
		os.date("%Y-%m-%d"),
		require("obsidian.templates").substitute_template_variables("{{date:YYYY-MM-DD}}", { partial_note = ordinary }),
		"ordinary template dates are unchanged"
	)
	vim.o.hidden = false
	assert(not pcall(periodic.open, settings, "monthly", "2034-02-01"), "unsaved source without hidden rejected")
	assert(vim.fn.filereadable(second .. "/" .. settings.monthly.folder .. "/2034-02.md") == 0, "no note created")
	vim.o.hidden = true

	local altered = vim.deepcopy(settings)
	altered.monthly.template = profile.templates.folder .. "/Missing"
	assert(not pcall(periodic.open, altered, "monthly", "2031-02-01"), "missing template rejected")
	assert(vim.fn.filereadable(second .. "/" .. settings.monthly.folder .. "/2031-02.md") == 0, "no partial note")
	altered.monthly.folder = "../escape"
	assert(not pcall(periodic.open, altered, "monthly", "2031-02-01"), "parent traversal rejected")
	vim.uv.fs_symlink(vim.fs.dirname(second), second .. "/linked")
	altered.monthly.folder = "linked"
	assert(not pcall(periodic.open, altered, "monthly", "2031-02-01"), "symlink path rejected")
	altered = vim.deepcopy(settings)
	vim.uv.fs_symlink(second .. "/" .. settings.monthly.template .. ".md", second .. "/linked-template.md")
	altered.monthly.template = "linked-template"
	assert(not pcall(periodic.open, altered, "monthly", "2031-02-01"), "symlink template rejected")
	assert(not pcall(periodic.open, settings, "hourly", nil), "unknown interval rejected")

	for _, command in ipairs({ "Periodic", "Weekly", "Monthly", "Quarterly", "Yearly" }) do
		vim.api.nvim_del_user_command("Obsidian" .. command)
	end
	periodic.setup({ enabled = false, settings = settings })
	equal(0, vim.fn.exists(":ObsidianPeriodic"), "no commands when disabled")
	local workspaces = profile.workspaces
	vim.g.dotfiles_obsidian = vim.tbl_extend("force", profile, { workspaces = {} })
	periodic.setup({ enabled = true, settings = settings })
	equal(0, vim.fn.exists(":ObsidianPeriodic"), "no commands without a vault")
	vim.g.dotfiles_obsidian = vim.tbl_extend("force", profile, { workspaces = workspaces })
	print("PASS: Obsidian periodic notes: commands, lazy loading, intervals, ISO years, templates, vaults, safety")
end

local ok, err = xpcall(check, debug.traceback)
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
