local function fail(message)
	error(message, 2)
end

local function assert_equal(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		fail(string.format("%s\nexpected: %s\nactual:   %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_contains(haystack, needle, label)
	if not haystack:find(needle, 1, true) then
		fail(string.format("%s: missing %q in %q", label, needle, haystack))
	end
end

local function mkdir(path)
	vim.fn.mkdir(path, "p")
end

local function write_lines(path, lines)
	mkdir(vim.fs.dirname(path))
	assert(vim.fn.writefile(lines, path) == 0, "failed to write " .. path)
end

local function read_lines(path)
	return vim.fn.readfile(path)
end

local function read_text(path)
	return table.concat(read_lines(path), "\n")
end

local function edit_file(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	vim.bo.filetype = "markdown"
	return vim.api.nvim_get_current_buf()
end

local function apply_change(lines, change)
	local out = {}
	for index = 1, change.from do
		out[#out + 1] = lines[index]
	end
	vim.list_extend(out, change.lines)
	for index = change.to + 1, #lines do
		out[#out + 1] = lines[index]
	end
	return out
end

local function has_item(items, predicate)
	for _, item in ipairs(items or {}) do
		if predicate(item) then
			return true, item
		end
	end
	return false
end

local function command(name, argument)
	local spec = { cmd = name }
	if argument ~= nil then
		spec.args = { argument }
	end
	vim.api.nvim_cmd(spec, {})
end

local function real(path)
	local absolute = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	return vim.fs.normalize(vim.uv.fs_realpath(absolute) or absolute):gsub("/+$", "")
end

local ok, err = pcall(function()
	vim.o.hidden = true
	local profile = vim.g.dotfiles_obsidian or {}
	assert_equal((profile.capture or {}).enabled, true, "generated capture flag")
	assert_equal((profile.references or {}).enabled, true, "generated references flag")
	assert_equal(profile.daily_notes.folder, "Journal", "generated daily folder")
	assert_equal(profile.daily_notes.date_format, "%Y/%m/%Y-%m-%d-%A", "generated daily format")
	assert_equal(profile.templates.folder, "Templates", "generated templates folder")
	assert_equal(profile.capture.questions_folder, "Knowledge/Questions", "generated questions folder")
	assert_equal(profile.capture.question_template, "Question.md", "generated question template")
	assert_equal(profile.capture.log_heading, "## Activity", "generated log heading")
	assert_equal(profile.references.people_folder, "Notes/People", "generated people folder")
	assert_equal(#profile.workspaces, 2, "generated workspaces")

	local commands = vim.api.nvim_get_commands({})
	for _, name in ipairs({ "ObsidianQuestion", "ObsidianAnswer", "ObsidianLog" }) do
		assert(commands[name], name .. " should be registered from the packaged plugin entry point")
	end
	for _, expected in ipairs({
		{ lhs = "<leader>oq", desc = "New Question Note" },
		{ lhs = "<leader>oa", desc = "Answer Question Note" },
		{ lhs = "<leader>ol", desc = "Add Daily Log Entry" },
	}) do
		local mapping = vim.fn.maparg(expected.lhs, "n", false, true)
		assert(mapping.desc == expected.desc, expected.lhs .. " should map its Obsidian capture action")
	end
	for _, lhs in ipairs({ "<leader>mq", "<leader>ma", "<leader>ml" }) do
		assert(vim.fn.maparg(lhs, "n") == "", lhs .. " should no longer be mapped")
	end
	assert(type(_G._dotfiles_obsidian_refs_register) == "function", "Blink registration hook should exist")

	local capture = require("mark.obsidian_capture")
	local refs = require("mark.obsidian_refs_source")
	local alpha = real(profile.workspaces[1].path)
	local beta = real(profile.workspaces[2].path)
	assert(alpha ~= beta, "test workspaces must differ")

	-- The migrated table-driven insertion cases exercise current and legacy
	-- timestamps, equal-time stability, fences, placeholders, and boundaries.
	local cases_path = assert(vim.env.DOTFILES_OBSIDIAN_LOG_CASES, "DOTFILES_OBSIDIAN_LOG_CASES is required")
	local cases = vim.json.decode(table.concat(read_lines(cases_path), "\n"))
	for _, case in ipairs(cases) do
		local change
		if case.question then
			change = capture.question_log_edit(case.input, case.question, case.time, { log_heading = case.heading })
		else
			change = capture.log_edit(case.input, case.text, case.time, { log_heading = case.heading })
		end
		assert_equal(apply_change(case.input, change), case.expected, "log case: " .. case.name)
	end

	local question_template = vim.fs.joinpath(alpha, "Templates", "Question.md")
	local beta_template = vim.fs.joinpath(beta, "Templates", "Question.md")
	local template_lines = {
		"---",
		"type: question",
		"date: {{date}}",
		"asked_in:",
		"answer:",
		"status: open",
		"resolved:",
		"sources: []",
		"ask:",
		"---",
		"# {{title}}",
		"- Where it came up: ",
		"",
		"## Answer",
		"-",
		"",
		"## Sources",
		"-",
	}
	write_lines(question_template, template_lines)
	write_lines(beta_template, template_lines)
	write_lines(vim.fs.joinpath(alpha, "Templates", "Daily Note.md"), {
		"# Daily",
		"",
		"## Activity",
		"- ",
		"",
		"> [!info] Template boundary",
	})
	write_lines(vim.fs.joinpath(beta, "Templates", "Daily Note.md"), { "# Daily", "", "## Activity", "- " })

	write_lines(vim.fs.joinpath(alpha, "Notes", "People", "Alice Example.md"), { "# Alice Example" })
	write_lines(vim.fs.joinpath(alpha, "Notes", "Contacts", "Bob Builder.md"), {
		"---",
		"type: person",
		"---",
		"# Bob Builder",
	})
	write_lines(vim.fs.joinpath(alpha, "Knowledge", "Questions", "Seed.md"), {
		"---",
		"type: question",
		"ask:",
		'  - "[[Carol Person]]"',
		"---",
	})
	write_lines(vim.fs.joinpath(alpha, "Notes", "Project.md"), {
		"---",
		"aliases:",
		"  - Launch Plan",
		"---",
		"# Project",
		"",
		"## Details",
	})
	refs.clear_cache()

	-- Opening a vault note exercises the real shared lazy loader and indexes the
	-- files above before prompt completion requests begin.
	local old_daily = vim.fs.joinpath(alpha, "Journal", "2024", "05", "2024-05-10-Friday.md")
	write_lines(old_daily, {
		"# Friday",
		"",
		"## Activity",
		"- ",
		"",
		"> [!tip] Keep this boundary",
	})
	edit_file(old_daily)
	vim.api.nvim_win_set_cursor(0, { 3, 0 })
	local question = "Why preserve 100% behavior?"
	command("ObsidianQuestion", question)
	local question_name = "Why preserve 100% behavior"
	local question_path = vim.fs.joinpath(alpha, "Knowledge", "Questions", question_name .. ".md")
	local question_text = read_text(question_path)
	assert_contains(question_text, "date: 2024-05-10", "question source date")
	assert_contains(question_text, 'asked_in: "[[2024-05-10-Friday]]"', "question backlink metadata")
	assert_contains(question_text, "# " .. question, "literal template replacement")
	assert_contains(
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
		"? [[" .. question_name .. "]]",
		"daily question log link"
	)

	-- Existing notes are linked but never overwritten.
	local existing_path = vim.fs.joinpath(alpha, "Knowledge", "Questions", "Existing.md")
	write_lines(existing_path, { "do not overwrite" })
	local topic = vim.fs.joinpath(alpha, "Notes", "Topic.md")
	write_lines(topic, { "context" })
	edit_file(topic)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	command("ObsidianQuestion", "Existing?")
	assert_equal(read_lines(existing_path), { "do not overwrite" }, "existing question preservation")
	assert_contains(
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
		"- ? [[Existing]]",
		"existing question link"
	)

	-- Weekly/monthly journals keep cursor-local insertion even below the daily root.
	local weekly = vim.fs.joinpath(alpha, "Journal", "Weekly", "2024-W19.md")
	write_lines(weekly, { "# Week", "cursor line", "## Activity", "- " })
	edit_file(weekly)
	vim.api.nvim_win_set_cursor(0, { 2, 0 })
	command("ObsidianQuestion", "Weekly placement?")
	local weekly_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	assert_equal(weekly_lines[3], "- ? [[Weekly placement]]", "non-daily journal cursor insertion")
	assert_equal(weekly_lines[5], "- ", "non-daily journal log remains untouched")

	-- Existing legacy daily notes nested under Daily retain their source date.
	local legacy = vim.fs.joinpath(alpha, "Journal", "Daily", "2023-02-03-Friday.md")
	write_lines(legacy, { "# Legacy", "", "## Activity", "- " })
	edit_file(legacy)
	command("ObsidianQuestion", "Legacy daily?")
	local legacy_question = vim.fs.joinpath(alpha, "Knowledge", "Questions", "Legacy daily.md")
	assert_contains(read_text(legacy_question), "date: 2023-02-03", "legacy daily source date")
	assert_contains(
		table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
		"? [[Legacy daily]]",
		"legacy daily log placement"
	)

	-- Prefix-similar workspace paths resolve to the containing workspace only.
	local beta_note = vim.fs.joinpath(beta, "Notes", "Other.md")
	write_lines(beta_note, { "# Other" })
	edit_file(beta_note)
	command("ObsidianQuestion", "Beta question?")
	assert(
		vim.uv.fs_stat(vim.fs.joinpath(beta, "Knowledge", "Questions", "Beta question.md")),
		"beta question should use beta workspace"
	)
	assert(
		not vim.uv.fs_stat(vim.fs.joinpath(alpha, "Knowledge", "Questions", "Beta question.md")),
		"beta question must not leak into alpha workspace"
	)
	assert_equal(refs.vault_for_path(beta_note, false), beta, "workspace path-boundary lookup")

	-- Answer a question linked from an older daily note. The answer and source
	-- mentions use configured people lookup and the source daily date.
	local answer_question = vim.fs.joinpath(alpha, "Knowledge", "Questions", "Answer me.md")
	write_lines(answer_question, {
		"---",
		"type: question",
		"date: 2022-01-02",
		'asked_in: "[[2022-01-02-Sunday]]"',
		"answer:",
		"status: open",
		"resolved:",
		"sources: []",
		"ask:",
		'  - "[[Alice Example]]"',
		"---",
		"# Answer me?",
		"",
		"## Answer",
		"-",
		"",
		"## Sources",
		"-",
	})
	local answer_source = vim.fs.joinpath(alpha, "Journal", "2022", "01", "2022-01-02-Sunday.md")
	write_lines(answer_source, { "# Sunday", "- ? [[Answer me]]" })
	edit_file(answer_source)
	vim.api.nvim_win_set_cursor(0, { 2, 4 })
	assert(capture.answer("Ask @Alice Example tomorrow", "@Bob Builder"), "answer capture should succeed")
	local answered = read_text(answer_question)
	assert_contains(answered, 'answer: "Ask [[Alice Example]] tomorrow"', "answer metadata")
	assert_contains(answered, "status: answered", "answer status")
	assert_contains(answered, 'resolved: "2022-01-02"', "answer source date")
	assert_contains(answered, '  - "[[Bob Builder]]"', "answer source metadata")
	assert_contains(answered, "- [[Bob Builder]]", "answer sources section")
	assert_equal(
		capture.link_mentions("mail a@b.com and [[@Alice Example]]", { "Alice Example" }),
		"mail a@b.com and [[@Alice Example]]",
		"mention exclusions"
	)

	-- Cancelling either question input or the source step of an answer makes no change.
	local original_input = vim.ui.input
	local before_questions = vim.fn.glob(vim.fs.joinpath(alpha, "Knowledge", "Questions", "*.md"), false, true)
	vim.ui.input = function(_, callback)
		callback(nil)
	end
	capture.prompt({})
	assert_equal(
		vim.fn.glob(vim.fs.joinpath(alpha, "Knowledge", "Questions", "*.md"), false, true),
		before_questions,
		"cancelled question prompt"
	)
	local before_answer = read_text(answer_question)
	local responses = { "A replacement", nil }
	vim.ui.input = function(_, callback)
		callback(table.remove(responses, 1))
	end
	edit_file(answer_source)
	vim.api.nvim_win_set_cursor(0, { 2, 4 })
	capture.prompt_answer()
	vim.ui.input = original_input
	assert_equal(read_text(answer_question), before_answer, "cancelled answer source prompt")

	-- People come from the configured folder, type: person notes under its
	-- parent, and existing question ask metadata.
	refs.clear_cache()
	assert_equal(refs.people(alpha), { "Alice Example", "Bob Builder", "Carol Person" }, "people lookup")
	local mention_items = refs.prompt_items(alpha, "ask @Ali")
	assert(
		has_item(mention_items.items, function(item)
			return item.insert == "@Alice Example"
		end),
		"prompt @ completion should include Alice"
	)

	-- Registering repeatedly is idempotent and the provider handles @ only, so
	-- obsidian-ls remains the sole normal-buffer [[ completion source.
	assert(_G._dotfiles_obsidian_refs_register(), "Blink source registration should succeed")
	assert(_G._dotfiles_obsidian_refs_register(), "Blink source re-registration should be safe")
	local blink_config = require("blink.cmp.config")
	assert(blink_config.sources.providers.obsidian_refs, "Blink provider should be configured")
	local source_lib = require("blink.cmp.sources.lib")
	local count = 0
	for _, id in ipairs(source_lib.per_filetype_provider_ids.markdown or {}) do
		if id == "obsidian_refs" then
			count = count + 1
		end
	end
	assert_equal(count, 1, "Blink filetype provider registration count")
	local source = refs.new()
	local completion
	source:get_completions(
		{ bufnr = vim.api.nvim_get_current_buf(), line = "@Ali", cursor = { 1, 4 } },
		function(result)
			completion = result
		end
	)
	assert(
		has_item(completion.items, function(item)
			return item.textEdit.newText == "[[Alice Example]]"
		end),
		"normal buffer @ completion"
	)
	source:get_completions(
		{ bufnr = vim.api.nvim_get_current_buf(), line = "[[Ali", cursor = { 1, 5 } },
		function(result)
			completion = result
		end
	)
	assert_equal(#completion.items, 0, "normal buffer [[ completion must not be duplicated")

	-- Use obsidian.nvim's real language server for prompt note completion. The
	-- shared source preserves its insertion strings, including aliases/headings.
	local function prompt_items(query, predicate)
		local result
		local found = vim.wait(3000, function()
			result = refs.prompt_items(alpha, query)
			return has_item(result.items, predicate)
		end, 100)
		return found, result
	end
	local found_project = prompt_items("[[Proj", function(item)
		return item.insert:find("Project", 1, true) ~= nil
	end)
	assert(found_project, "real obsidian-ls note completion should return Project")
	local found_alias = prompt_items("[[Launch", function(item)
		return item.insert:find("Launch Plan", 1, true) ~= nil
	end)
	assert(found_alias, "real obsidian-ls completion should preserve aliases")
	local found_heading = prompt_items("[[Project#Det", function(item)
		return item.insert:find("#Details", 1, true) ~= nil
	end)
	assert(found_heading, "real obsidian-ls completion should preserve headings")

	-- Daily log capture uses the real obsidian.nvim daily-note path/template,
	-- never switches away from the source buffer, and writes existing unsaved
	-- destination edits together with the new entry.
	local source_path = vim.fs.joinpath(alpha, "Notes", "Capture source.md")
	write_lines(source_path, { "# Source", "keep" })
	local source_buf = edit_file(source_path)
	vim.api.nvim_buf_set_lines(source_buf, 1, 2, false, { "keep unsaved" })
	vim.api.nvim_win_set_cursor(0, { 2, 3 })
	local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
	local source_cursor = vim.api.nvim_win_get_cursor(0)
	assert(vim.bo[source_buf].modified, "source should start modified")
	local today_path = vim.fs.joinpath(alpha, "Journal", os.date("%Y"), os.date("%m"), os.date("%Y-%m-%d-%A") .. ".md")
	vim.fn.delete(today_path)
	command("ObsidianLog", "Captured @Alice Example 100%")
	assert_equal(vim.api.nvim_get_current_buf(), source_buf, "daily capture source buffer")
	assert_equal(vim.api.nvim_win_get_cursor(0), source_cursor, "daily capture source cursor")
	assert_equal(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false), source_lines, "daily capture source text")
	assert(vim.bo[source_buf].modified, "daily capture must preserve unsaved source edits")
	local today_text = read_text(today_path)
	assert_contains(today_text, "## Activity", "real daily template")
	assert_contains(today_text, "Captured [[Alice Example]] 100%", "daily capture content")

	local daily_buf = vim.fn.bufnr(today_path)
	assert(daily_buf > 0 and vim.api.nvim_buf_is_loaded(daily_buf), "daily buffer should remain loaded")
	vim.api.nvim_buf_set_lines(daily_buf, -1, -1, false, { "unsaved destination detail" })
	assert(vim.bo[daily_buf].modified, "destination should be modified before capture")
	assert(capture.capture_log("second entry", alpha), "capture with unsaved destination should succeed")
	local updated_today = read_text(today_path)
	assert_contains(updated_today, "unsaved destination detail", "unsaved destination preservation")
	assert_contains(updated_today, "second entry", "second daily capture")

	local before_cancel = updated_today
	vim.ui.input = function(_, callback)
		callback(nil)
	end
	command("ObsidianLog")
	vim.ui.input = original_input
	assert_equal(read_text(today_path), before_cancel, "cancelled daily log prompt")

	vim.bo[daily_buf].readonly = true
	local readonly_before = vim.api.nvim_buf_get_lines(daily_buf, 0, -1, false)
	assert(not capture.capture_log("must not write", alpha), "read-only daily capture should fail")
	assert_equal(vim.api.nvim_buf_get_lines(daily_buf, 0, -1, false), readonly_before, "read-only daily buffer")
	vim.bo[daily_buf].readonly = false

	-- A real BufWritePre failure happens after insertion; the pending entry and
	-- modified flag remain in the destination buffer for recovery.
	local failure_group = vim.api.nvim_create_augroup("obsidian_capture_write_failure_test", { clear = true })
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = failure_group,
		buffer = daily_buf,
		once = true,
		callback = function()
			error("forced write failure")
		end,
	})
	assert(not capture.capture_log("recover this entry", alpha), "forced write failure should be reported")
	assert(vim.bo[daily_buf].modified, "failed write should leave the daily buffer modified")
	assert_contains(
		table.concat(vim.api.nvim_buf_get_lines(daily_buf, 0, -1, false), "\n"),
		"recover this entry",
		"failed-write recovery content"
	)
	vim.api.nvim_clear_autocmds({ group = failure_group })

	-- Loader failure is reported without touching the destination.
	local profile_copy = vim.deepcopy(profile)
	capture.setup({
		enabled = true,
		profile = profile_copy,
		ensure_loaded = function()
			return false
		end,
	})
	local before_loader_failure = vim.api.nvim_buf_get_lines(daily_buf, 0, -1, false)
	assert(not capture.capture_log("loader failure", alpha), "loader failure should abort capture")
	assert_equal(
		vim.api.nvim_buf_get_lines(daily_buf, 0, -1, false),
		before_loader_failure,
		"loader failure destination"
	)

	print("PASS: configurable Obsidian capture, answer, log, and reference completion")
end)

if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
