local treesitter = require("mark.treesitter")
local lazy = require("mark.lazy")

local function start_treesitter(ev)
	if treesitter.disabled_for_buffer(ev.buf) then
		-- Native Lua and Markdown ftplugins can start highlighting before this
		-- callback. Enforce guards for normal files; special buffers own their setup.
		if vim.bo[ev.buf].buftype == "" then
			pcall(vim.treesitter.stop, ev.buf)
		end
		return
	end
	if not treesitter.ensure_runtime() then
		return
	end
	local lang_ok, lang = pcall(treesitter.language_for, vim.bo[ev.buf].filetype)
	if not lang_ok or not lang then
		return
	end
	pcall(vim.treesitter.start, ev.buf, lang)
end

-- Keep only the parser start path early. Parser availability checks and
-- textobject maps are deferred below so opening a file does less before first
-- paint.
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("treesitter_start"),
	callback = start_treesitter,
})

local textobjects
local function ensure_ts_textobjects()
	if textobjects then
		return textobjects
	end
	local loaded, load_err = lazy.packadd("nvim-treesitter-textobjects", { trigger = "textobject keymap" })
	if not loaded then
		return nil, load_err
	end
	local select, select_err = lazy.require("nvim-treesitter-textobjects.select")
	if not select then
		return nil, select_err
	end
	local move, move_err = lazy.require("nvim-treesitter-textobjects.move")
	if not move then
		return nil, move_err
	end
	textobjects = { select = select, move = move }
	return textobjects
end

--- Create a textobject selection function for a capture
local function ts_select(capture)
	return function()
		local modules, load_err = ensure_ts_textobjects()
		if not modules then
			return false, load_err
		end
		return pcall(modules.select.select_textobject, capture, "textobjects")
	end
end

local function ts_move(modules, goto_fn_name, capture)
	local move = modules.move[goto_fn_name]
	if type(move) ~= "function" then
		return false, "missing Tree-sitter textobject movement " .. goto_fn_name
	end
	return pcall(move, capture, "textobjects")
end

--- Create a textobject movement function that wraps at buffer boundaries
local function ts_move_factory(goto_fn_name, wrap_cmd)
	return function(capture)
		return function()
			local modules, load_err = ensure_ts_textobjects()
			if not modules then
				return false, load_err
			end
			local start_pos = vim.api.nvim_win_get_cursor(0)
			local moved, move_err = ts_move(modules, goto_fn_name, capture)
			if not moved then
				return false, move_err
			end
			local current_pos = vim.api.nvim_win_get_cursor(0)
			if start_pos[1] == current_pos[1] and start_pos[2] == current_pos[2] then
				vim.cmd("norm! " .. wrap_cmd)
				local wrap_pos = vim.api.nvim_win_get_cursor(0)
				moved, move_err = ts_move(modules, goto_fn_name, capture)
				if not moved then
					pcall(vim.api.nvim_win_set_cursor, 0, start_pos)
					return false, move_err
				end
				current_pos = vim.api.nvim_win_get_cursor(0)
				if wrap_pos[1] == current_pos[1] and wrap_pos[2] == current_pos[2] then
					pcall(vim.api.nvim_win_set_cursor, 0, start_pos)
				end
			end
			return true
		end
	end
end

-- Register textobject keymaps after startup. The mappings are cold-path editing
-- helpers; their callbacks packadd/require nvim-treesitter-textobjects on first
-- actual use.
later(function()
	local selections = {
		{ "c", "comment", "Comment" },
		{ "f", "function", "Function" },
		{ "L", "loop", "Loop" },
		{ "T", "class", "Type/Class" },
		{ "P", "parameter", "Parameter" },
		{ "S", "statement", "Statement" },
	}
	for _, part in ipairs({ { "a", "outer", "Outer" }, { "i", "inner", "Inner" } }) do
		for _, selection in ipairs(selections) do
			local key, capture, desc = unpack(selection)
			vim.keymap.set({ "x", "o" }, part[1] .. key, ts_select("@" .. capture .. "." .. part[2]), {
				desc = part[3] .. " " .. desc,
			})
		end
	end

	local movements = {
		{ "a", "@assignment.lhs", "Assignment", "start" },
		{ "f", "@function.outer", "Function", "start" },
		{ "o", "@class.outer", "Type/Class", "start" },
		{ "A", "@assignment.rhs", "End of Assignment", "end" },
		{ "F", "@function.outer", "End of Function", "end" },
		{ "O", "@class.outer", "End of Type/Class", "end" },
	}
	for _, direction in ipairs({ { "]", "next", "Next", "gg" }, { "[", "previous", "Previous", "G" } }) do
		local prefix, name, label, wrap_cmd = unpack(direction)
		local move = {
			start = ts_move_factory("goto_" .. name .. "_start", wrap_cmd),
			["end"] = ts_move_factory("goto_" .. name .. "_end", wrap_cmd),
		}
		for _, movement in ipairs(movements) do
			local key, capture, desc, boundary = unpack(movement)
			vim.keymap.set({ "n", "x", "o" }, prefix .. key, move[boundary](capture), { desc = label .. " " .. desc })
		end
	end
end)
