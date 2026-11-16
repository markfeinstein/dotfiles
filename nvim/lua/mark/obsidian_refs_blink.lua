local M = {}

local state_key = "dotfiles_obsidian_refs_blink_state"
local group_name = "dotfiles_obsidian_refs_blink"

local function profile()
	return vim.g.dotfiles_obsidian or {}
end

local function enabled()
	return (profile().references or {}).enabled == true and #(profile().workspaces or {}) > 0
end

local function state()
	local current = rawget(_G, state_key)
	if not current then
		current = { registered = false }
		rawset(_G, state_key, current)
	end
	return current
end

local function install_prompt_labels(config)
	local cmdline = config.sources.providers.cmdline
	if not cmdline or cmdline._dotfiles_obsidian_labels then
		return
	end
	local previous = cmdline.transform_items
	cmdline.transform_items = function(ctx, items)
		if previous then
			items = previous(ctx, items)
		end
		if not vim.g.dotfiles_obsidian_prompt then
			return items
		end
		for _, item in ipairs(items) do
			local text = item.textEdit and item.textEdit.newText or item.label
			local name = text:match("^%[%[[^%]|]+|([^%]]+)%]%]$")
				or text:match("^%[%[([^%]|]+)")
				or text:match("^@(.+)$")
			if name then
				item.label = name
				item.filterText = name
			end
		end
		return items
	end
	cmdline._dotfiles_obsidian_labels = true

	-- Blink provider objects cache their config after initialization.
	local sources = require("blink.cmp.sources.lib")
	local provider = sources.providers and sources.providers.cmdline
	if provider and provider.config then
		provider.config.transform_items = cmdline.transform_items
	end
end

function M.register()
	if not enabled() then
		return false
	end
	local current = state()
	if type(_G._ensure_blink_cmp) == "function" and not _G._ensure_blink_cmp("obsidian_refs") then
		return false
	end
	local ok, blink = pcall(require, "blink.cmp")
	if not ok then
		return false
	end
	local config = require("blink.cmp.config")
	if current.registered and config.sources.providers.obsidian_refs then
		install_prompt_labels(config)
		return true
	end
	if not config.sources.providers.obsidian_refs then
		blink.add_source_provider("obsidian_refs", {
			module = "mark.obsidian_refs_source",
			name = "People",
			score_offset = 20,
		})
		blink.add_filetype_source("markdown", "obsidian_refs")
	end
	install_prompt_labels(config)
	current.registered = true
	return true
end

function M.setup()
	local group = vim.api.nvim_create_augroup(group_name, { clear = true })
	_G._dotfiles_obsidian_refs_register = nil
	if not enabled() then
		return
	end

	_G._dotfiles_obsidian_refs_register = M.register
	vim.api.nvim_create_autocmd("InsertEnter", {
		group = group,
		callback = function()
			if vim.bo.filetype == "markdown" and M.register() then
				return true
			end
		end,
		desc = "Register Obsidian @ people completion with blink.cmp",
	})

	if package.loaded["blink.cmp"] and vim.bo.filetype == "markdown" then
		M.register()
	end
end

return M
