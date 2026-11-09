-- Blink completion is managed by Nix and provides LSP, snippet, buffer,
-- path, and Obsidian-aware markdown completion.

local blink_loaded = false
local lazy = require("mark.lazy")
local log = require("mark.log").get("blink")

local blink_keymap = { ["<C-space>"] = false }
blink_keymap["<C-y>"] = {
	function(cmp)
		if cmp.is_visible() then
			return cmp.select_and_accept()
		end
		if vim.lsp.inline_completion.get() then
			return true
		end
	end,
	"fallback",
}
for i = 1, 9 do
	local index = i
	blink_keymap["<A-" .. i .. ">"] = {
		function(cmp)
			cmp.accept({ index = index })
		end,
	}
end

-- lua_ls can return a useful full list marked incomplete, followed by an empty
-- list for the next prefix. Override Blink's public source boundary instead of
-- mutating vim.lsp.Client.request, and only change the single-lua_ls case.
local function lsp_get_completions(source, context, callback)
	local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/completion" })
	local lua_ls_only = #clients == 1 and clients[1].name == "lua_ls"
	return source:get_completions(context, function(response)
		if lua_ls_only and response then
			response.is_incomplete_forward = false
		end
		callback(response)
	end)
end

local function ensure_blink(trigger)
	if blink_loaded then
		return true
	end

	if type(trigger) ~= "string" then
		trigger = "InsertEnter/CmdlineEnter"
	end

	-- These are optional Nix plugins. pcall keeps this compatible with an older
	-- generation where they may still be start plugins on the runtimepath.
	local pack_opts = { trigger = trigger }
	lazy.packadd("blink.cmp", { trigger = trigger, bang = true })
	lazy.packadd("lazydev.nvim", pack_opts)
	lazy.packadd("blink-emoji.nvim", pack_opts)
	lazy.packadd("blink-nerdfont.nvim", pack_opts)

	local blink_opts = {
		cmdline = {
			completion = {
				list = { selection = { preselect = false } },
				menu = {
					auto_show = true,
					draw = {
						columns = {
							{ "item_idx" },
							{ "label", "label_description", gap = 1 },
							{ "kind" },
							{ "source_name" },
						},
					},
				},
			},
			keymap = { preset = "inherit" },
		},
		completion = {
			keyword = { range = "full" },
			accept = { auto_brackets = { enabled = false } },
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 300, -- Increased from 200ms to reduce CPU during fast typing
			},
			ghost_text = { enabled = true },
			list = { selection = { preselect = false } },
			menu = {
				draw = {
					columns = {
						{ "item_idx" },
						{ "kind_icon" },
						{ "label", "label_description", gap = 1 },
						{ "kind" },
						{ "source_name" },
					},
					components = {
						item_idx = {
							text = function(ctx)
								return ctx.idx == 10 and "0" or ctx.idx >= 10 and " " or tostring(ctx.idx)
							end,
							highlight = "BlinkCmpItemIdx",
						},
						kind_icon = {
							text = function(ctx)
								local icon, hl = require("mini.icons").get("lsp", ctx.kind)
								-- Stash highlight from same call for reuse in highlight callback
								ctx._mini_icon_hl = hl
								return icon
							end,
							highlight = function(ctx)
								-- Reuse highlight resolved in text callback (same render cycle)
								return ctx._mini_icon_hl or select(2, require("mini.icons").get("lsp", ctx.kind))
							end,
						},
						kind = {
							highlight = function(ctx)
								return ctx._mini_icon_hl or select(2, require("mini.icons").get("lsp", ctx.kind))
							end,
						},
					},
					gap = 2,
					treesitter = { "lua", "markdown" },
				},
			},
			trigger = {
				show_on_backspace = true,
				show_on_backspace_in_keyword = true,
			},
		},
		keymap = blink_keymap,
		sources = {
			default = { "snippets", "lsp", "buffer", "path", "emoji", "nerdfont" },
			per_filetype = {
				lua = { "lazydev", inherit_defaults = true },
				-- Octo buffers: Add GitHub-specific completion
				octo = { "snippets", "buffer", "path", "emoji" },
			},
			providers = {
				lazydev = { module = "lazydev.integrations.blink" },
				lsp = {
					async = true,
					timeout_ms = 50,
					fallbacks = {},
					override = { get_completions = lsp_get_completions },
				},
				snippets = {
					score_offset = -10,
					-- Uses native vim.snippet engine (0.12+)
					-- Searches stdpath('config')/snippets by default
				},
				buffer = { async = true, score_offset = -5 },
				path = { async = true, fallbacks = {} },
				emoji = {
					module = "blink-emoji",
					score_offset = 15,
					should_show_items = function()
						return vim.tbl_contains({ "gitcommit", "markdown", "octo" }, vim.bo.filetype)
					end,
				},
				nerdfont = {
					module = "blink-nerdfont",
					name = "Nerd Fonts",
					score_offset = 15,
					opts = { trigger = ":-)" },
				},
			},
		},
	}

	local blink = lazy.require("blink.cmp", { notify = true })
	if not blink then
		return false
	end

	local ok_setup, setup_err = pcall(blink.setup, blink_opts)
	if not ok_setup then
		log.error("failed to set up blink.cmp", setup_err)
		vim.notify("Failed to set up blink.cmp: " .. tostring(setup_err), vim.log.levels.ERROR)
		return false
	end

	blink_loaded = true
	return true
end

_G._ensure_blink_cmp = ensure_blink

vim.api.nvim_create_autocmd({ "InsertEnter", "CmdlineEnter" }, {
	group = vim.api.nvim_create_augroup("blink_lazy_load"),
	once = true,
	callback = ensure_blink,
	desc = "Lazy-load blink.cmp on first completion-capable mode",
})
