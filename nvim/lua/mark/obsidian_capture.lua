-- Configurable Obsidian question, answer, and daily-log capture.
--
-- All vault policy comes from vim.g.dotfiles_obsidian. The shared Obsidian
-- plugin supplies its lazy loader through setup(), so this module never creates
-- an independent plugin loader or autosave timer.

local M = {}

local state_key = "dotfiles_obsidian_capture_state"
local prompt_namespace = vim.api.nvim_create_namespace("dotfiles_obsidian_prompt_trigger")
local command_names = { "ObsidianQuestion", "ObsidianAnswer", "ObsidianLog" }
local mappings = { "<leader>oq", "<leader>oa", "<leader>ol" }
local completion_vault

local function current_state()
	return rawget(_G, state_key)
end

local function profile()
	local state = current_state()
	return (state and state.profile) or vim.g.dotfiles_obsidian or {}
end

local function capture_config()
	return profile().capture or {}
end

local function reference_config()
	return profile().references or {}
end

local function normalize_path(path)
	local absolute = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	local normalized = vim.fs.normalize(vim.uv.fs_realpath(absolute) or absolute)
	return normalized == "/" and normalized or normalized:gsub("/+$", "")
end

local function is_within(path, root)
	return path == root or vim.startswith(path, root .. "/")
end

local function workspace_roots()
	local roots = {}
	for _, workspace in ipairs(profile().workspaces or {}) do
		roots[#roots + 1] = normalize_path(workspace.path)
	end
	return roots
end

-- Vault containing path, or the first configured vault when fallback is true.
local function vault_for(path, fallback)
	local roots = workspace_roots()
	if path ~= "" then
		local absolute = normalize_path(path)
		for _, root in ipairs(roots) do
			if is_within(absolute, root) then
				return root, true
			end
		end
	end
	return fallback and roots[1] or nil, false
end

local function questions_folder()
	return capture_config().questions_folder or "Questions"
end

local function question_template()
	return capture_config().question_template or "Question.md"
end

local function log_heading()
	return capture_config().log_heading or "## Log"
end

local function references_enabled()
	return reference_config().enabled == true
end

local function to_filename(question)
	local name = question:gsub('[\\/:*?"<>|#^%[%]]', ""):gsub("%s+", " ")
	return vim.trim(name):gsub("[%.%s]+$", "")
end

local function yaml_quote(value)
	return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- Nested and legacy daily notes retain an ISO date prefix in the filename.
-- Requiring that prefix avoids treating weekly/monthly journals as daily notes.
local function daily_date(source_path, vault)
	local daily_notes = profile().daily_notes or {}
	local daily_root = normalize_path(vim.fs.joinpath(vault, daily_notes.folder or "Daily"))
	local source = source_path ~= "" and normalize_path(source_path) or ""
	if is_within(source, daily_root) and source ~= daily_root then
		return source:match("/(%d%d%d%d%-%d%d%-%d%d)[^/]*%.md$")
	end
end

local function note_date(source_path, vault)
	return daily_date(source_path, vault) or os.date("%Y-%m-%d")
end

local function render(template_lines, question, date, source_link)
	local out = {}
	for _, original in ipairs(template_lines) do
		local line = original:gsub("{{date}}", date):gsub("{{title}}", (question:gsub("%%", "%%%%")))
		if source_link then
			if line == "asked_in:" then
				line = "asked_in: " .. yaml_quote(source_link)
			elseif line == "- Where it came up: " then
				line = line .. source_link
			end
		end
		out[#out + 1] = line
	end
	return out
end

local function insert_link(bufnr, winid, name)
	local row = vim.api.nvim_win_get_cursor(winid)[1]
	local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
	local indent = line:match("^(%s*)") or ""
	local entry = indent .. "- ? [[" .. name .. "]]"
	if line:match("^%s*[-*]?%s*%??%s*$") then
		vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, { entry })
	else
		vim.api.nvim_buf_set_lines(bufnr, row, row, false, { entry })
		row = row + 1
	end
	vim.api.nvim_win_set_cursor(winid, { row, #entry })
end

-- Timestamped top-level log entries. Accept the current bold-time-with-dash
-- format and the legacy plain, bold-only, and bracketed timestamp styles.
local function log_time(line)
	local text = line:match("^[-*]%s+(.+)$")
	if not text then
		return nil
	end
	text = text:gsub("^%*%*", ""):gsub("^%[", "")
	local hour, minute, rest = text:match("^(%d%d?):(%d%d)(.*)$")
	if not hour then
		return nil
	end
	rest = rest:gsub("^%*%*", ""):gsub("^%]", "")
	if tonumber(hour) < 24 and tonumber(minute) < 60 and (rest == "" or rest:match("^%s")) then
		return tonumber(hour) * 60 + tonumber(minute)
	end
end

local function normalized_heading(heading)
	return vim.trim(heading):gsub("%s+#+%s*$", "")
end

local function is_log_heading(line, heading)
	return normalized_heading(line) == normalized_heading(heading)
end

-- Return a zero-based, end-exclusive buffer edit. Existing blocks are never
-- sorted or rewritten, so untimed history and continuation lines stay intact.
function M.log_edit(lines, text, time, opts)
	opts = opts or {}
	local heading = opts.log_heading or log_heading()
	local entry = "- **" .. time .. "** - " .. text
	local first, finish, fence
	for index, line in ipairs(lines) do
		local marker = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
		if fence then
			local close = line:match("^%s*(" .. fence:sub(1, 1) .. "+)%s*$")
			if close and #close >= #fence then
				fence = nil
			end
		elseif marker then
			fence = marker
		elseif not first and is_log_heading(line, heading) then
			first = index + 1
		elseif first and (line:match("^#+%s") or line:match("^>%s*%[!")) then
			finish = index
			break
		end
	end
	if not first then
		local added = {}
		if #lines > 0 and lines[#lines] ~= "" then
			added[#added + 1] = ""
		end
		vim.list_extend(added, { heading, "", entry })
		return { from = #lines, to = #lines, lines = added, row = #lines + #added - 1 }
	end

	finish = finish or (#lines + 1)
	local placeholder, empty = nil, true
	for index = first, finish - 1 do
		if lines[index]:match("^[-*]%s*%??%s*$") then
			placeholder = placeholder or index
		elseif not lines[index]:match("^%s*$") then
			empty = false
		end
	end
	if empty and placeholder then
		return { from = placeholder - 1, to = placeholder, lines = { entry }, row = placeholder - 1 }
	end

	local at = finish
	local now = log_time(entry)
	local in_fence
	for index = first, finish - 1 do
		local marker = lines[index]:match("^%s*(```+)") or lines[index]:match("^%s*(~~~+)")
		if in_fence then
			local close = lines[index]:match("^%s*(" .. in_fence:sub(1, 1) .. "+)%s*$")
			if close and #close >= #in_fence then
				in_fence = nil
			end
		elseif marker then
			in_fence = marker
		else
			local existing = log_time(lines[index])
			if existing and existing > now then
				at = index
				break
			end
		end
	end
	if at == finish then
		while at > first and lines[at - 1]:match("^%s*$") do
			at = at - 1
		end
	end
	if at > first and lines[at - 1]:match("^[-*]%s*%??%s*$") then
		return { from = at - 2, to = at - 1, lines = { entry }, row = at - 2 }
	end
	local added = { entry }
	local row = at - 1
	if empty then
		table.insert(added, 1, "")
		row = row + 1
	end
	if at == finish and finish <= #lines then
		added[#added + 1] = ""
	end
	return { from = at - 1, to = at - 1, lines = added, row = row }
end

function M.question_log_edit(lines, name, time, opts)
	return M.log_edit(lines, "? [[" .. name .. "]]", time, opts)
end

local function insert_log_link(bufnr, winid, name)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local change = M.question_log_edit(lines, name, os.date("%H:%M"))
	vim.api.nvim_buf_set_lines(bufnr, change.from, change.to, false, change.lines)
	local entry = vim.api.nvim_buf_get_lines(bufnr, change.row, change.row + 1, false)[1]
	vim.api.nvim_win_set_cursor(winid, { change.row + 1, #entry })
end

function M.create(question, opts)
	opts = opts or {}
	question = vim.trim(question or "")
	if question == "" then
		return false
	end

	local bufnr, winid = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	local source_path = vim.api.nvim_buf_get_name(bufnr)
	local vault, in_vault = vault_for(source_path, true)
	if not vault then
		vim.notify("No Obsidian workspace is configured", vim.log.levels.WARN)
		return false
	end

	local name = to_filename(question)
	if name == "" then
		vim.notify("Question has no usable filename characters", vim.log.levels.WARN)
		return false
	end

	local directory = vim.fs.joinpath(vault, questions_folder())
	local path = vim.fs.joinpath(directory, name .. ".md")
	local existed = vim.uv.fs_stat(path) ~= nil
	if not existed then
		local templates = profile().templates or {}
		local template_relative = vim.fs.joinpath(templates.folder or "Templates", question_template())
		local ok, template = pcall(vim.fn.readfile, vim.fs.joinpath(vault, template_relative))
		if not ok or #template == 0 then
			vim.notify("Question template not found: " .. template_relative, vim.log.levels.ERROR)
			return false
		end
		local source_link = in_vault
				and vim.bo[bufnr].filetype == "markdown"
				and ("[[" .. vim.fn.fnamemodify(source_path, ":t:r") .. "]]")
			or nil
		vim.fn.mkdir(directory, "p")
		if vim.fn.writefile(render(template, question, note_date(source_path, vault), source_link), path) ~= 0 then
			vim.notify("Failed to write " .. path, vim.log.levels.ERROR)
			return false
		end
	end

	local linkable = in_vault and vim.bo[bufnr].modifiable and vim.bo[bufnr].filetype == "markdown"
	if linkable then
		if daily_date(source_path, vault) then
			insert_log_link(bufnr, winid, name)
		else
			insert_link(bufnr, winid, name)
		end
	end
	if opts.open or not linkable then
		vim.cmd.edit(vim.fn.fnameescape(path))
	end
	vim.notify((existed and "Linked existing question: " or "Created question: ") .. name, vim.log.levels.INFO)
	return true, path, existed
end

local function find_line(lines, predicate, from, to)
	for index = from or 1, to or #lines do
		if predicate(lines[index]) then
			return index
		end
	end
end

local function frontmatter_bounds(lines)
	if lines[1] ~= "---" then
		return nil
	end
	local close = find_line(lines, function(line)
		return line == "---"
	end, 2)
	return close and 1, close
end

local function fm_value(lines, close, key)
	for index = 2, close - 1 do
		local value = lines[index]:match("^" .. key .. ":%s*(.-)%s*$")
		if value then
			return value:gsub('^"(.*)"$', "%1"), index
		end
	end
end

local function fm_set(lines, close, key, value)
	local _, index = fm_value(lines, close, key)
	local line = key .. ": " .. value
	if index then
		lines[index] = line
		return close
	end
	table.insert(lines, close, line)
	return close + 1
end

local function fm_append_list(lines, close, key, item)
	local value, index = fm_value(lines, close, key)
	local entry = "  - " .. item
	if not index then
		table.insert(lines, close, key .. ":")
		table.insert(lines, close + 1, entry)
		return close + 2
	end
	if value == "[]" or value == "" then
		lines[index] = key .. ":"
	elseif value:match("^%[.*%]$") then
		lines[index] = key .. ":"
		local at = index + 1
		for part in value:sub(2, -2):gmatch("[^,]+") do
			table.insert(lines, at, "  - " .. vim.trim(part))
			at, close = at + 1, close + 1
		end
	elseif not value:match("^%s*$") then
		lines[index] = key .. ":"
		table.insert(lines, index + 1, "  - " .. value)
		close = close + 1
	end
	local last = index
	while lines[last + 1] and lines[last + 1]:match("^%s+%- ") do
		last = last + 1
		if vim.trim(lines[last]) == "- " .. item then
			return close
		end
	end
	table.insert(lines, last + 1, entry)
	return close + 1
end

local function add_to_section(lines, heading, text, replace_empty_bullet)
	local start = find_line(lines, function(line)
		return vim.trim(line) == heading
	end)
	if not start then
		while #lines > 0 and vim.trim(lines[#lines]) == "" do
			table.remove(lines)
		end
		vim.list_extend(lines, { "", heading, "", text })
		return
	end
	local stop = find_line(lines, function(line)
		return line:match("^#+%s") ~= nil
	end, start + 1) or (#lines + 1)
	local last = start
	for index = start + 1, stop - 1 do
		if vim.trim(lines[index]) ~= "" then
			last = index
		end
	end
	if replace_empty_bullet and last > start and lines[last]:match("^%s*%-%s*$") then
		lines[last] = text
	elseif last == start and stop - start > 2 then
		lines[start + 2] = text
	else
		table.insert(lines, last + 1, text)
	end
end

local function yaml_scalar(value)
	if value:match("^[%w%s%.,%-%(%)/]+$") and not value:match("^%s") then
		return value
	end
	return yaml_quote(value)
end

function M.apply_answer(lines, answer, source, date)
	lines = vim.deepcopy(lines)
	local _, close = frontmatter_bounds(lines)
	if not close then
		return nil, "note has no frontmatter"
	end
	local summary = vim.trim((answer:match("^(.-)\n%s*\n") or answer):gsub("%s*\n%s*", " "))
	close = fm_set(lines, close, "answer", yaml_scalar(summary))
	close = fm_set(lines, close, "status", "answered")
	close = fm_set(lines, close, "resolved", yaml_quote(date))
	if source and source ~= "" then
		close = fm_append_list(lines, close, "sources", yaml_quote(source))
	end
	local body = vim.list_slice(lines, close + 1)
	local answer_lines = vim.split(answer, "\n", { plain = true })
	add_to_section(body, "## Answer", answer_lines[1], false)
	if #answer_lines > 1 then
		local at
		for index, line in ipairs(body) do
			if line == answer_lines[1] then
				at = index
				break
			end
		end
		if at then
			for index = 2, #answer_lines do
				table.insert(body, at + index - 1, answer_lines[index])
			end
		end
	end
	if source and source ~= "" then
		add_to_section(body, "## Sources", "- " .. source, true)
	end
	local out = vim.list_slice(lines, 1, close)
	vim.list_extend(out, body)
	return out
end

local function answer_target()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	local vault = vault_for(path, false)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local _, close = frontmatter_bounds(lines)
	if close and fm_value(lines, close, "type") == "question" then
		return path, bufnr
	end
	local link = vim.api.nvim_get_current_line():match("%[%[([^%]|#]+)")
	if link and vault then
		local candidate = vim.fs.joinpath(vault, questions_folder(), link .. ".md")
		if vim.uv.fs_stat(candidate) then
			return candidate, vim.fn.bufnr(candidate)
		end
	end
end

local function known_people(vault)
	local ok, references = pcall(require, "mark.obsidian_refs_source")
	local names = ok and vim.deepcopy(references.people(vault)) or {}
	table.sort(names, function(left, right)
		return #left > #right
	end)
	return names
end

function M.link_mentions(text, people)
	local out, index = {}, 1
	while index <= #text do
		local at = text:find("@", index, true)
		if not at then
			break
		end
		out[#out + 1] = text:sub(index, at - 1)
		local before = at > 1 and text:sub(at - 1, at - 1) or " "
		local prefix = text:sub(1, at)
		local open_at = select(2, prefix:find(".*%[%[")) or 0
		local close_at = select(2, prefix:find(".*%]%]")) or 0
		local rest = text:sub(at + 1)
		local name, consumed
		if not (before:match("[%w._]") or open_at > close_at) then
			for _, candidate in ipairs(people) do
				local after = rest:sub(#candidate + 1, #candidate + 1)
				if rest:sub(1, #candidate):lower() == candidate:lower() and not after:match("[%w_]") then
					name, consumed = candidate, #candidate
					break
				end
			end
			if not name then
				local first = rest:match("^[A-Za-z][%w_'%-]*")
				if first then
					local more = rest:sub(#first + 1):match("^( [A-Z][%w_'%-]*)")
					name = first
					while more do
						name = name .. more
						more = rest:sub(#name + 1):match("^( [A-Z][%w_'%-]*)")
					end
					consumed = #name
				end
			end
		end
		if name then
			out[#out + 1] = "[[" .. name .. "]]"
			index = at + 1 + consumed
		else
			out[#out + 1] = "@"
			index = at + 1
		end
	end
	out[#out + 1] = text:sub(index)
	return table.concat(out)
end

function M.source_default(lines)
	local _, close = frontmatter_bounds(lines)
	if not close then
		return ""
	end
	local ask, index = fm_value(lines, close, "ask")
	if not index then
		return ""
	end
	if ask == "" or ask == "[]" then
		local item = (lines[index + 1] or ""):match("^%s+%-%s+(.-)%s*$")
		ask = item and item:gsub('^"(.*)"$', "%1") or ""
	end
	local link = ask:match("^%[%[([^%]|#]+)")
	return link and ("@" .. vim.trim(link):gsub("^@", "")) or ask
end

local function answer_date()
	local path = vim.api.nvim_buf_get_name(0)
	local vault = vault_for(path, true)
	return vault and note_date(path, vault) or os.date("%Y-%m-%d")
end

function M.answer(answer, source)
	local path, bufnr = answer_target()
	if not path then
		vim.notify("Open a Question note, or put the cursor on a [[question]] link", vim.log.levels.WARN)
		return false
	end
	answer = vim.trim(answer or "")
	if answer == "" then
		return false
	end
	local vault = vault_for(path, true)
	local people = known_people(vault)
	answer = M.link_mentions(answer, people)
	source = vim.trim(source or "")
	if source ~= "" then
		source = M.link_mentions(source, people)
	end

	local loaded = bufnr and bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
	local ok, lines = pcall(function()
		return loaded and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or vim.fn.readfile(path)
	end)
	if not ok then
		vim.notify("Could not read " .. path .. ": " .. tostring(lines), vim.log.levels.ERROR)
		return false
	end
	local out, err = M.apply_answer(lines, answer, source, answer_date())
	if not out then
		vim.notify("Could not answer " .. path .. ": " .. err, vim.log.levels.ERROR)
		return false
	end
	if loaded then
		local changed, change_err = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, out)
		if not changed then
			vim.notify("Failed to update " .. path .. ": " .. tostring(change_err), vim.log.levels.ERROR)
			return false
		end
		local written, write_err = pcall(vim.api.nvim_buf_call, bufnr, function()
			vim.cmd("silent write")
		end)
		if not written then
			vim.notify("Failed to write " .. path .. ": " .. tostring(write_err), vim.log.levels.ERROR)
			return false
		end
	elseif vim.fn.writefile(out, path) ~= 0 then
		vim.notify("Failed to write " .. path, vim.log.levels.ERROR)
		return false
	end
	vim.notify("Answered: " .. vim.fn.fnamemodify(path, ":t:r"), vim.log.levels.INFO)
	return true
end

function _G.DotfilesObsidianComplete(arglead, line, position)
	local ok, references = pcall(require, "mark.obsidian_refs_source")
	if not ok then
		return {}
	end
	arglead = arglead or ""
	local before = type(line) == "string" and line:sub(1, tonumber(position) or #line) or arglead
	local result = references.prompt_items(completion_vault, before)
	if #result.items == 0 then
		return {}
	end
	local head = arglead == before and #before > #result.word and before:sub(1, #before - #result.word) or ""
	local out = {}
	for _, item in ipairs(result.items) do
		out[#out + 1] = head .. item.insert
	end
	return out
end

local function open_menu_if_triggered()
	if not completion_vault or vim.fn.getcmdtype() ~= "@" then
		return
	end
	local before = vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1)
	if not (before:match("@$") or before:match("%[%[$")) or before:match("[%w._]@$") then
		return
	end
	local ok, blink = pcall(require, "blink.cmp")
	if ok and blink.show then
		blink.show()
	elseif vim.fn.wildmenumode() == 0 then
		vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "n", false)
	end
end

local function watch_triggers(enable)
	if enable then
		vim.on_key(function(raw)
			if raw == "@" or raw == "[" then
				vim.schedule(open_menu_if_triggered)
			end
		end, prompt_namespace)
	else
		vim.on_key(nil, prompt_namespace)
	end
end

function M.field(opts, on_confirm)
	local input = { prompt = opts.prompt .. ": ", default = opts.default }
	local complete = references_enabled()
	if complete then
		local state = current_state()
		if state and state.ensure_loaded then
			state.ensure_loaded("Obsidian capture prompt")
		end
		completion_vault = opts.vault
		if type(_G._dotfiles_obsidian_refs_register) == "function" then
			_G._dotfiles_obsidian_refs_register()
		end
		vim.g.dotfiles_obsidian_prompt = true
		watch_triggers(true)
		input.completion = "customlist,v:lua.DotfilesObsidianComplete"
	end
	vim.ui.input(input, function(value)
		if complete then
			watch_triggers(false)
			vim.g.dotfiles_obsidian_prompt = nil
			completion_vault = nil
		end
		on_confirm(value)
	end)
end

function M.prompt(opts)
	local vault = vault_for(vim.api.nvim_buf_get_name(0), true)
	M.field({ prompt = "New question", vault = vault }, function(question)
		question = vim.trim(question or "")
		if question ~= "" then
			M.create(M.link_mentions(question, known_people(vault)), opts)
		end
	end)
end

function M.prompt_answer()
	local path, bufnr = answer_target()
	if not path then
		vim.notify("Open a Question note, or put the cursor on a [[question]] link", vim.log.levels.WARN)
		return
	end
	local loaded = bufnr and bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
	local ok, lines = pcall(function()
		return loaded and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or vim.fn.readfile(path)
	end)
	if not ok then
		vim.notify("Could not read " .. path .. ": " .. tostring(lines), vim.log.levels.ERROR)
		return
	end
	local vault = vault_for(path, true)
	M.field({ prompt = "Answer", vault = vault }, function(answer)
		answer = vim.trim(answer or "")
		if answer == "" then
			return
		end
		M.field({ prompt = "Source", default = M.source_default(lines), vault = vault }, function(source)
			if source ~= nil then
				M.answer(answer, source)
			end
		end)
	end)
end

function M.capture_log(text, vault)
	text = vim.trim(text or "")
	if text == "" then
		return false
	end
	vault = vault or vault_for(vim.api.nvim_buf_get_name(0), true)
	if not vault then
		vim.notify("No Obsidian workspace is configured", vim.log.levels.WARN)
		return false
	end
	local state = current_state()
	local ok, err = pcall(function()
		if not state or not state.ensure_loaded or not state.ensure_loaded("daily log capture") then
			error("Could not load obsidian.nvim")
		end
		local daily = require("obsidian.daily")
		local now = os.time()
		local path = tostring(daily.daily_note_path(now, vault))
		local bufnr = vim.fn.bufnr(path)
		local loaded = bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
		if not loaded and not vim.uv.fs_stat(path) then
			daily.daily({ date = now, dir = vault }):write()
		end
		bufnr = loaded and bufnr or vim.fn.bufadd(path)
		vim.fn.bufload(bufnr)
		if not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly or vim.bo[bufnr].buftype ~= "" then
			error("Today's daily note is not writable")
		end
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("silent checktime")
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local entry = M.link_mentions(text, known_people(vault))
			local change = M.log_edit(lines, entry, os.date("%H:%M", now))
			vim.api.nvim_buf_set_lines(bufnr, change.from, change.to, false, change.lines)
			vim.cmd("silent update")
		end)
	end)
	if not ok then
		vim.notify("Daily log capture failed: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	vim.notify("Added entry to today's daily Log", vim.log.levels.INFO)
	return true
end

local function run_log(text)
	local vault = vault_for(vim.api.nvim_buf_get_name(0), true)
	if text and text ~= "" then
		M.capture_log(text, vault)
	else
		M.field({ prompt = "Daily log", vault = vault }, function(value)
			M.capture_log(value, vault)
		end)
	end
end

function M.teardown()
	watch_triggers(false)
	completion_vault = nil
	vim.g.dotfiles_obsidian_prompt = nil
	for _, name in ipairs(command_names) do
		pcall(vim.api.nvim_del_user_command, name)
	end
	for _, lhs in ipairs(mappings) do
		pcall(vim.keymap.del, "n", lhs)
	end
	rawset(_G, state_key, nil)
end

function M.setup(opts)
	M.teardown()
	opts = opts or {}
	local configured_profile = opts.profile or vim.g.dotfiles_obsidian or {}
	if not opts.enabled or #(configured_profile.workspaces or {}) == 0 then
		return false
	end
	rawset(_G, state_key, {
		profile = configured_profile,
		ensure_loaded = assert(opts.ensure_loaded, "ensure_loaded is required"),
	})

	vim.api.nvim_create_user_command("ObsidianQuestion", function(command)
		local create_opts = { open = command.bang }
		if command.args ~= "" then
			M.create(command.args, create_opts)
		else
			M.prompt(create_opts)
		end
	end, { nargs = "*", bang = true, desc = "Create an Obsidian Question note and link it here" })
	vim.keymap.set("n", "<leader>oq", function()
		M.prompt()
	end, { desc = "New Question Note" })

	vim.api.nvim_create_user_command("ObsidianAnswer", function(command)
		if command.args ~= "" then
			M.answer(command.args)
		else
			M.prompt_answer()
		end
	end, { nargs = "*", desc = "Answer the current or linked Obsidian Question note" })
	vim.keymap.set("n", "<leader>oa", function()
		M.prompt_answer()
	end, { desc = "Answer Question Note" })

	vim.api.nvim_create_user_command("ObsidianLog", function(command)
		run_log(command.args)
	end, { nargs = "*", desc = "Save an entry to today's daily Log" })
	vim.keymap.set("n", "<leader>ol", function()
		run_log()
	end, { desc = "Add Daily Log Entry" })
	return true
end

M.daily_date = daily_date
M.note_date = note_date
M.render = render
M.to_filename = to_filename
M.vault_for = vault_for

return M
