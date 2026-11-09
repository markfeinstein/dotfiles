local M = {}

-- fzf keeps the original grep entry as field four. The first three fields are
-- search-only metadata, so changing --nth never changes what fzf-lua previews
-- or opens. The unit separator avoids collisions with valid path characters
-- such as ':' and with ordinary source text.
M.grep_delimiter = string.char(31)

---@param entry string
---@param opts table
---@param modules? table
---@return string
function M.grep_transform(entry, opts, modules)
	modules = modules or {
		path = require("fzf-lua.path"),
		utils = require("fzf-lua.utils"),
	}

	local location = modules.path.entry_to_file(entry, opts)
	local path = location.path or ""
	local line = location.line or 0
	-- fzf-lua already owns location parsing. This fail-closed default keeps
	-- filtering safe if its display format changes: content-only mode matches
	-- nothing rather than accidentally matching a filename.
	local content = ""
	local stripped = location.stripped or modules.utils.strip_ansi_coloring(entry)
	local prefix = string.format("%s:%d:%d:", path, line, location.col or 0)
	if stripped:sub(1, #prefix) == prefix then
		content = stripped:sub(#prefix + 1)
	end

	return table.concat({ path, content, tostring(line), entry }, M.grep_delimiter)
end

function M.grep_options()
	local delimiter = "[" .. M.grep_delimiter .. "]"
	local actions = require("fzf-lua.actions")
	local function file_action(fn)
		-- The hide profile runs file actions through fzf's execute-silent action.
		-- Unlike accepted output, its placeholder is not affected by --accept-nth,
		-- so select the preserved original entry explicitly instead of passing the
		-- search-only metadata fields to fzf-lua's path parser.
		return { fn = fn, field_index = "{+4}" }
	end
	return {
		multiprocess = true,
		fn_transform = [[return require("mark.fzf").grep_transform]],
		field_index_expr = "{1}",
		line_field_index = "{3}",
		actions = {
			enter = file_action(actions.file_edit_or_qf),
			["ctrl-s"] = file_action(actions.file_split),
			["ctrl-v"] = file_action(actions.file_vsplit),
			["ctrl-t"] = file_action(actions.file_tabedit),
			["alt-q"] = file_action(actions.file_sel_to_qf),
			["alt-Q"] = file_action(actions.file_sel_to_ll),
		},
		fzf_opts = {
			["--delimiter"] = delimiter,
			["--with-nth"] = "4",
			["--nth"] = "1",
			["--accept-nth"] = "4",
		},
		keymap = {
			fzf = {
				["alt-r"] = "change-with-nth(4)+change-nth(1)+change-prompt(All> )",
				["alt-p"] = "change-with-nth(1)+change-nth(1)+change-prompt(Path> )",
				["alt-c"] = "change-with-nth(2)+change-nth(1)+change-prompt(Content> )",
			},
		},
		header = "CTRL-G Regex/Fuzzy | ALT-R All | ALT-P Path | ALT-C Content",
	}
end

return M
