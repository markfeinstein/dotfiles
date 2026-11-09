-- Native vim._core.ui2 floating cmdline, messages, dialogs, and pager.

-- Keep private UI2 probing isolated so disabled/unavailable modes can be
-- exercised without loading any UI2-only helpers.
local ui2_bootstrap = require("mark.ui2_bootstrap")
local ui2 = ui2_bootstrap.probe()
if not ui2 then
	return
end

local api = vim.api
local search_count = require("mark.search_count")
local log = require("mark.log").get("ui2")

-- Single augroup for all autocmds (prevents duplicates on :source)
local augroup = api.nvim_create_augroup("ui2_config")

local ui2_config = {
	msg = {
		targets = {
			default = "msg",
			list_cmd = "pager",
			quickfix = "pager",
			verbose = "pager",
		},
	},
}

-- Prevent invalid references from reaching Neovim's private UI2 internals.
local function valid_ui2_ref(ref, is_valid)
	if not ref or type(ref) ~= "number" or ref <= 0 or not is_valid(ref) then
		return nil
	end
	return ref
end

local function get_valid_ui2_buf(buf_ref)
	return valid_ui2_ref(buf_ref, api.nvim_buf_is_valid)
end

local function get_valid_ui2_win(win_ref)
	return valid_ui2_ref(win_ref, api.nvim_win_is_valid)
end

-- Enable UI2 with per-kind message routing before installing wrappers/hooks.
if not ui2_bootstrap.enable(ui2, ui2_config, { log = log }) then
	return
end

local function config_module(name)
	local ok, module = pcall(require, name)
	if ok then
		return module
	end
	local source = debug.getinfo(1, "S").source:sub(2)
	local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
	return dofile(vim.fs.joinpath(root, "lua", name:gsub("%.", "/") .. ".lua"))
end

local context = {
	api = api,
	augroup = augroup,
	get_valid_ui2_buf = get_valid_ui2_buf,
	get_valid_ui2_win = get_valid_ui2_win,
	log = log,
	search_count = search_count,
	ui2 = ui2,
}
config_module("mark.ui2.cmdline").setup(context)
config_module("mark.ui2.pager").setup(context)
