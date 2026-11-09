local bigfile = require("mark.bigfile")
local timer = require("mark.timer")

local M = {}

local SPECIAL_FILETYPES = {
	cmd = true,
	dialog = true,
	msg = true,
	pager = true,
}

local function maxcount(sc)
	return sc.maxcount or 999
end

function M.buffer_is_eligible(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local buftype = vim.bo[bufnr].buftype
	if buftype ~= "" and buftype ~= "nofile" then
		return false
	end
	if SPECIAL_FILETYPES[vim.bo[bufnr].filetype] then
		return false
	end
	if bigfile.is_guarded(bufnr) then
		return false
	end
	return true
end

function M.format_position(sc)
	if not sc or not sc.total then
		return nil
	end
	if sc.total == 0 then
		return "[No match]", "DiagnosticSignError"
	end
	if sc.incomplete and sc.incomplete > 0 then
		return string.format("[%d/%d+]", sc.current or 0, sc.total), "DiagnosticSignWarn"
	end
	if sc.total > maxcount(sc) then
		return string.format("[%d/>%d]", sc.current or 0, maxcount(sc)), "DiagnosticSignWarn"
	end
	return string.format("[%d/%d]", sc.current or 0, sc.total), "DiagnosticSignWarn"
end

function M.format_matches(sc)
	if not sc or not sc.total then
		return nil
	end
	if sc.total == 0 then
		return "[No match]", "DiagnosticSignError"
	end
	if sc.incomplete and sc.incomplete > 0 then
		return string.format("[%d matches+]", sc.total), "DiagnosticSignWarn"
	end
	if sc.total > maxcount(sc) then
		return string.format("[>%d matches]", maxcount(sc)), "DiagnosticSignWarn"
	end
	return string.format("[%d matches]", sc.total), "DiagnosticSignWarn"
end

local function substitute_command_start(text)
	local command, pos = text:match("^%%?(%a+)()")
	return command and ("substitute"):sub(1, #command) == command and pos or nil
end

local function valid_substitute_delimiter(delimiter)
	return delimiter ~= ""
		and not delimiter:match("%s")
		and not delimiter:match("%w")
		and delimiter ~= "\\"
		and delimiter ~= '"'
		and delimiter ~= "|"
end

function M.substitute_pattern(text)
	if type(text) ~= "string" then
		return nil
	end
	local delimiter_pos = substitute_command_start(text)
	if not delimiter_pos or delimiter_pos > #text then
		return nil
	end
	local delimiter = text:sub(delimiter_pos, delimiter_pos)
	if not valid_substitute_delimiter(delimiter) then
		return nil
	end
	local pattern_start = delimiter_pos + 1
	local i = pattern_start
	while i <= #text do
		local char = text:sub(i, i)
		if char == "\\" then
			i = i + 2
		elseif char == delimiter then
			return text:sub(pattern_start, i - 1)
		else
			i = i + 1
		end
	end
	return text:sub(pattern_start)
end

function M.new_counter(opts)
	opts = opts or {}
	return {
		delay_ms = opts.delay_ms or 60,
		generation = {},
		next_generation = 0,
		timers = {},
	}
end

local function bump(counter, owner)
	-- Do not reuse a generation after an owner is forgotten and requested again.
	counter.next_generation = counter.next_generation + 1
	counter.generation[owner] = counter.next_generation
	return counter.next_generation
end

function M.cancel(counter, owner)
	if not counter then
		return
	end
	if counter.generation[owner] ~= nil then
		bump(counter, owner)
	end
	timer.cancel_slot(counter.timers, owner)
end

function M.forget(counter, owner)
	counter.generation[owner] = nil
	timer.cancel_slot(counter.timers, owner)
end

function M.cancel_all(counter)
	if not counter then
		return
	end
	for owner in pairs(counter.timers) do
		timer.cancel_slot(counter.timers, owner)
	end
	for owner in pairs(counter.generation) do
		bump(counter, owner)
	end
end

function M.request(counter, owner, opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local gen = bump(counter, owner)
	timer.replace(counter.timers, owner, opts.delay_ms or counter.delay_ms, function()
		if counter.generation[owner] ~= gen then
			return
		end
		if not M.buffer_is_eligible(bufnr) then
			if opts.on_skip then
				opts.on_skip(bufnr)
			end
			return
		end
		if opts.validate and not opts.validate(bufnr, gen) then
			return
		end
		local searchcount_fn = opts.searchcount_fn or vim.fn.searchcount
		local ok, sc = pcall(searchcount_fn, opts.searchcount_opts or { timeout = 20 })
		if counter.generation[owner] ~= gen then
			return
		end
		if not ok or not sc then
			return
		end
		if opts.apply then
			opts.apply(sc, bufnr, gen)
		end
	end)
end

return M
