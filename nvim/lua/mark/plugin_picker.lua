local M = {}

local lazy = require("mark.lazy")
local fzf_window = require("mark.fzf_window")
local uv = vim.uv

local function add_unique(items, seen, value)
	if value and value ~= "" and not seen[value] then
		seen[value] = true
		items[#items + 1] = value
	end
end

local function loaded_plugin_paths(runtime_paths)
	local loaded = {}
	for _, path in ipairs(runtime_paths) do
		loaded[uv.fs_realpath(path) or vim.fs.normalize(path)] = true
	end
	return loaded
end

local function config_files(config_root)
	local paths = {}
	local seen = {}
	for _, pattern in ipairs({ "init.lua", "plugin/**/*.lua", "after/**/*.lua", "lua/**/*.lua" }) do
		for _, path in ipairs(vim.fn.globpath(config_root, pattern, false, true)) do
			local stat = uv.fs_stat(path)
			if stat and stat.type == "file" then
				add_unique(paths, seen, vim.fs.normalize(path))
			end
		end
	end
	table.sort(paths)

	return vim.tbl_map(function(path)
		local lines = vim.fn.readfile(path)
		return {
			path = path,
			relative = vim.fs.relpath(config_root, path) or path,
			stem = vim.fn.fnamemodify(path, ":t:r"):lower():gsub("[^%w]", ""),
			lines = lines,
			lower = table.concat(lines, "\n"):lower(),
		}
	end, paths)
end

local function plugin_terms(name)
	local terms = {}
	local seen = {}
	local lower = name:lower()
	local base = lower:gsub("%.nvim$", ""):gsub("%-nvim$", ""):gsub("^nvim%-", ""):gsub("^vim%-", "")

	add_unique(terms, seen, lower)
	add_unique(terms, seen, lower:gsub("%.", "-"))
	add_unique(terms, seen, lower:gsub("%-", "."))
	if #base >= 4 then
		add_unique(terms, seen, base)
		add_unique(terms, seen, base:gsub("%.", "-"))
		add_unique(terms, seen, base:gsub("%-", "."))
	end
	return terms, base:gsub("[^%w]", "")
end

local function matching_configs(name, files)
	local matches = {}
	local terms, plugin_key = plugin_terms(name)
	for _, config in ipairs(files) do
		local matched = config.stem == plugin_key
		if not matched then
			for _, term in ipairs(terms) do
				if config.lower:find(term, 1, true) then
					matched = true
					break
				end
			end
		end
		if matched then
			matches[#matches + 1] = config
		end
	end
	return matches
end

---@param opts? { packpath?: string, config_root?: string, runtime_paths?: string[] }
---@return table[]
function M.collect(opts)
	opts = opts or {}
	local packpath = opts.packpath or vim.o.packpath
	local config_root = vim.fs.normalize(opts.config_root or vim.fn.stdpath("config"))
	local files = config_files(config_root)
	local loaded_paths = loaded_plugin_paths(opts.runtime_paths or vim.api.nvim_list_runtime_paths())
	local plugins = {}
	local seen = {}

	for _, root in ipairs(vim.split(packpath, ",", { plain = true, trimempty = true })) do
		for _, kind in ipairs({ "start", "opt" }) do
			for _, path in ipairs(vim.fn.globpath(root, "pack/hm/" .. kind .. "/*", false, true)) do
				local stat = uv.fs_stat(path)
				local name = vim.fs.basename(path)
				if stat and stat.type == "directory" and not seen[name] then
					seen[name] = true
					local normalized_path = vim.fs.normalize(path)
					local resolved_path = uv.fs_realpath(normalized_path) or normalized_path
					local loaded = loaded_paths[resolved_path] == true
					plugins[#plugins + 1] = {
						name = name,
						kind = kind,
						loaded = loaded,
						trigger = loaded and (kind == "start" and "startup" or lazy.load_trigger(name) or "unknown")
							or nil,
						path = normalized_path,
						configs = matching_configs(name, files),
					}
				end
			end
		end
	end

	table.sort(plugins, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return plugins
end

---@param plugin table
---@return string[]
function M.preview_lines(plugin)
	local lines = {
		plugin.name,
		string.rep("=", #plugin.name),
		"state: " .. (plugin.loaded and "loaded" or "not loaded"),
		"trigger: " .. (plugin.trigger or "none"),
		"package: " .. (plugin.kind == "opt" and "optional" or "start"),
		"path: " .. plugin.path,
		"",
	}

	if #plugin.configs == 0 then
		lines[#lines + 1] = "No matching local Lua configuration found."
		return lines
	end

	for index, config in ipairs(plugin.configs) do
		if index > 1 then
			lines[#lines + 1] = ""
		end
		lines[#lines + 1] = "-- " .. config.relative
		lines[#lines + 1] = string.rep("-", #config.relative + 3)
		vim.list_extend(lines, config.lines)
	end
	return lines
end

local function make_previewer(entry_by_line)
	local builtin = require("fzf-lua.previewer.builtin")
	local PluginPreviewer = builtin.base:extend()

	function PluginPreviewer:new(o, opts, fzf_win)
		PluginPreviewer.super.new(self, o, opts, fzf_win)
		setmetatable(self, PluginPreviewer)
		return self
	end

	function PluginPreviewer:populate_preview_buf(entry_line)
		local plugin = entry_by_line[entry_line]
		local tmpbuf = self:get_tmp_buffer()
		vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, plugin and M.preview_lines(plugin) or { "Plugin not found" })
		vim.bo[tmpbuf].filetype = "lua"
		self:set_preview_buf(tmpbuf)
		self.win:update_preview_title(plugin and plugin.name or "Plugin config")
		self.win:update_preview_scrollbar()
	end

	return PluginPreviewer
end

function M.open()
	local plugins = M.collect()
	if #plugins == 0 then
		vim.notify("No Home Manager Neovim plugins found", vim.log.levels.WARN)
		return
	end

	local entries = {}
	local entry_by_line = {}
	for _, plugin in ipairs(plugins) do
		local state = plugin.loaded and ("loaded (" .. plugin.trigger .. ")") or "not loaded"
		local line = string.format("%-28s %s", state, plugin.name)
		entries[#entries + 1] = line
		entry_by_line[line] = plugin
	end

	require("fzf-lua").fzf_exec(entries, {
		prompt = "Installed plugins> ",
		previewer = make_previewer(entry_by_line),
		winopts = {
			on_create = fzf_window.on_create(),
			preview = {
				horizontal = "right:65%",
				vertical = "down:60%",
			},
		},
		actions = {
			["default"] = function(selected)
				local plugin = entry_by_line[selected[1]]
				local config = plugin and plugin.configs[1]
				if config then
					vim.cmd.edit(vim.fn.fnameescape(config.path))
				else
					vim.notify(
						"No matching local config for " .. (plugin and plugin.name or "plugin"),
						vim.log.levels.INFO
					)
				end
			end,
		},
	})
end

return M
