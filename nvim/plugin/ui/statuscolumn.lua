-- Custom statuscolumn with fold, git, mark, and sign columns

local SYMBOL_RANK = {
	debug = 1,
	diagnostic = 2,
	git = 3,
	mark = 4,
	sign = 5,
}

local sign_cache = {}
local sign_cache_redraw_ns = vim.api.nvim_create_namespace("statuscolumn_sign_cache")
local pending_diagnostics = {}
local icon_cache = {}
local minidiff_ns = nil
local fillchars_cache = vim.opt.fillchars:get()

local function escape_statuscolumn(text)
	return tostring(text or ""):gsub("%%", "%%%%")
end

local function sign_type(name)
	if name:find("Dap", 1, true) then
		return "debug"
	end
	if name:find("Diagnostic", 1, true) then
		return "diagnostic"
	end
	if name:find("MiniDiff", 1, true) then
		return "git"
	end
	return "sign"
end

local function mark_text(mark)
	if type(mark) ~= "string" or #mark < 2 then
		return nil
	end
	local text = mark:sub(2)
	if not text:match("^[a-zA-Z]$") then
		return nil
	end
	return text
end

local function sign_tie_key(sign)
	return sign.name or sign.text or ""
end

local function symbol_precedes(candidate, current)
	if not current then
		return true
	end
	local candidate_rank = SYMBOL_RANK[candidate.type] or SYMBOL_RANK.sign
	local current_rank = SYMBOL_RANK[current.type] or SYMBOL_RANK.sign
	if candidate_rank ~= current_rank then
		return candidate_rank < current_rank
	end
	if candidate.priority ~= current.priority then
		return candidate.priority > current.priority
	end
	return sign_tie_key(candidate) < sign_tie_key(current)
end

local function add_symbol(by_line, lnum, sign)
	if symbol_precedes(sign, by_line[lnum]) then
		by_line[lnum] = sign
	end
end

local function buf_signs(buf)
	local cached = sign_cache[buf]
	if cached then
		return cached
	end

	local by_line = {}
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true, type = "sign" })
	for _, extmark in ipairs(extmarks) do
		local lnum = extmark[2] + 1
		local detail = extmark[4] or {}
		local name = detail.sign_hl_group or detail.sign_name or ""
		add_symbol(by_line, lnum, {
			name = name,
			type = sign_type(name),
			text = detail.sign_text or "",
			texthl = detail.sign_hl_group or "SignColumn",
			priority = detail.priority or 0,
		})
	end

	local marks = vim.fn.getmarklist(buf)
	vim.list_extend(marks, vim.fn.getmarklist())
	for _, mark in ipairs(marks) do
		local pos = mark.pos or {}
		local text = mark_text(mark.mark)
		if pos[1] == buf and text then
			local lnum = pos[2]
			if lnum and lnum > 0 then
				add_symbol(by_line, lnum, {
					name = mark.mark,
					type = "mark",
					text = text,
					texthl = "DiagnosticHint",
					priority = 0,
				})
			end
		end
	end

	sign_cache[buf] = by_line
	return by_line
end

local function get_git_hl_for_line(buf, lnum)
	if minidiff_ns == nil or minidiff_ns == false then
		local ns = vim.api.nvim_get_namespaces()["MiniDiffViz"]
		minidiff_ns = ns or false
	end
	if not minidiff_ns then
		return nil
	end

	local marks = vim.api.nvim_buf_get_extmarks(buf, minidiff_ns, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true })
	for _, mark in ipairs(marks) do
		local detail = mark[4] or {}
		local hl = detail.number_hl_group or detail.sign_hl_group
		if hl and hl:find("MiniDiff", 1, true) then
			return hl
		end
	end
	return nil
end

local function fold_sign(buf, lnum, foldclosed_lnum)
	if foldclosed_lnum == lnum then
		return {
			text = fillchars_cache.foldclose or icons.folds.close,
			texthl = get_git_hl_for_line(buf, lnum) or "Folded",
		}
	end

	local level = vim.fn.foldlevel(lnum)
	if level <= 0 then
		return nil
	end
	local prev = lnum > 1 and vim.fn.foldlevel(lnum - 1) or 0
	if level > prev then
		return {
			text = fillchars_cache.foldopen or icons.folds.open,
			texthl = get_git_hl_for_line(buf, lnum) or "FoldColumn",
		}
	end
end

local function icon(sign)
	if not sign then
		return "  "
	end

	local key = table.concat({ sign.text or "", sign.texthl or "" }, "\0")
	local cached = icon_cache[key]
	if cached then
		return cached
	end

	local text = vim.fn.strcharpart(tostring(sign.text or ""), 0, 2)
	local width = vim.fn.strdisplaywidth(text)
	if width < 2 then
		text = text .. string.rep(" ", 2 - width)
	end
	text = escape_statuscolumn(text)

	if sign.texthl and sign.texthl ~= "" then
		cached = "%#" .. sign.texthl .. "#" .. text .. "%*"
	else
		cached = text
	end

	icon_cache[key] = cached
	return cached
end

_G._statuscolumn = _G._statuscolumn or {}

local augroup = vim.api.nvim_create_augroup("statuscolumn_config")

-- Sign/extmark mutations do not change b:changedtick and Neovim has no
-- SignChanged event. Keep one full sign scan per buffer per redraw instead of
-- retaining a cache across redraws, where plugin and user signs could go stale.
vim.api.nvim_set_decoration_provider(sign_cache_redraw_ns, {
	on_start = function()
		sign_cache = {}
	end,
})

function _G._statuscolumn.invalidate(buf)
	if buf == 0 then
		buf = vim.api.nvim_get_current_buf()
	end
	if buf and vim.api.nvim_buf_is_valid(buf) then
		sign_cache[buf] = nil
	else
		sign_cache = {}
	end

	local redraw = { statuscolumn = true }
	if buf and vim.api.nvim_buf_is_valid(buf) then
		redraw.buf = buf
	end
	pcall(vim.api.nvim__redraw, redraw)
end

function _G._statuscolumn.get()
	if vim.v.virtnum ~= 0 then
		return ""
	end

	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	local wo = vim.wo[win]
	local nu = wo.number
	local rnu = wo.relativenumber
	local lnum = vim.v.lnum
	local foldclosed_lnum = vim.fn.foldclosed(lnum)
	local fold = fold_sign(buf, lnum, foldclosed_lnum)
	local symbol = buf_signs(buf)[lnum]

	local number = ""
	if nu or rnu then
		local current = vim.v.relnum == 0
		local num = tostring(current and nu and vim.v.lnum or (rnu and vim.v.relnum or vim.v.lnum))
		local field_width = math.max(1, wo.numberwidth - 1, #tostring(vim.api.nvim_buf_line_count(buf)))
		local padding = string.rep(" ", math.max(0, field_width - #num))
		-- Let the highlighted cursor-line number claim the left edge of the field;
		-- surrounding relative numbers remain right-aligned for easy scanning.
		local text = current and (num .. padding .. " ") or (padding .. num .. " ")
		local hl = current and "CursorLineNr" or "LineNr"
		number = "%#" .. hl .. "#" .. text .. "%*"
	end

	-- Signs sit left of the number, folds sit right of it, next to the code they
	-- fold. Same split snacks.nvim uses.
	return "%@v:lua._statuscolumn.click_fold@" .. icon(symbol) .. number .. icon(fold) .. "%T"
end

function _G._statuscolumn.click_fold()
	local pos = vim.fn.getmousepos()
	local win = pos and pos.winid ~= 0 and pos.winid
		or tonumber(vim.g.statusline_winid)
		or vim.api.nvim_get_current_win()
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	-- 0.13 sets v:lnum to the clicked row for statuscolumn click callbacks.
	local lnum = vim.v.lnum
	if lnum <= 0 or lnum > vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)) then
		return
	end

	vim.api.nvim_win_set_cursor(win, { lnum, 1 })
	vim.api.nvim_win_call(win, function()
		if vim.fn.foldlevel(lnum) > 0 then
			vim.cmd("normal! za")
		end
	end)
end

vim.api.nvim_create_autocmd("DiagnosticChanged", {
	group = augroup,
	callback = function(ev)
		if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
			pending_diagnostics[ev.buf] = true
			return
		end
		vim.schedule(function()
			_G._statuscolumn.invalidate(ev.buf)
		end)
	end,
	desc = "Redraw statuscolumn after diagnostics change",
})

vim.api.nvim_create_autocmd("BufWritePost", {
	group = augroup,
	callback = vim.schedule_wrap(function(ev)
		_G._statuscolumn.invalidate(ev.buf)
	end),
	desc = "Invalidate statuscolumn sign cache on write",
})

vim.api.nvim_create_autocmd({ "InsertLeave", "CursorHoldI" }, {
	group = augroup,
	callback = function(ev)
		if not pending_diagnostics[ev.buf] then
			return
		end
		pending_diagnostics[ev.buf] = nil
		vim.schedule(function()
			_G._statuscolumn.invalidate(ev.buf)
		end)
	end,
	desc = "Refresh deferred diagnostic signs in statuscolumn",
})

vim.api.nvim_create_autocmd("OptionSet", {
	group = augroup,
	pattern = "fillchars",
	callback = function()
		fillchars_cache = vim.opt.fillchars:get()
	end,
	desc = "Refresh cached fillchars for statuscolumn",
})

vim.api.nvim_create_autocmd("MarkSet", {
	group = augroup,
	callback = function(ev)
		local mark = (ev.data and ev.data.name) or ev.match or ""
		mark = mark:gsub("^'", "")
		if not mark:match("^[a-zA-Z]$") then
			return
		end
		if mark:match("^%u$") then
			_G._statuscolumn.invalidate()
		else
			_G._statuscolumn.invalidate(ev.buf)
		end
	end,
	desc = "Invalidate statuscolumn mark cache when native marks change",
})

vim.api.nvim_create_autocmd("BufWipeout", {
	group = augroup,
	callback = function(ev)
		sign_cache[ev.buf] = nil
		pending_diagnostics[ev.buf] = nil
	end,
	desc = "Drop wiped buffer from statuscolumn sign cache",
})

vim.api.nvim_create_autocmd("User", {
	group = augroup,
	pattern = "MiniDiffUpdated",
	callback = function(ev)
		minidiff_ns = nil
		_G._statuscolumn.invalidate(ev.buf)
	end,
	desc = "Invalidate statuscolumn MiniDiff namespace cache",
})

vim.o.statuscolumn = "%!v:lua._statuscolumn.get()"
