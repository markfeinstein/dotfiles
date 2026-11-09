-- Lazy which-key setup.
-- Independent from the private floating-UI adapter so keybinding hints remain
-- available when UI2 is unavailable or intentionally disabled.

local lazy = require("mark.lazy")

-- Load on the first supported prefix so its initial hint popup is still shown
-- while no idle startup work is spent on which-key when it is never used.

local which_key_loaded = false
local function setup_which_key()
	if which_key_loaded then
		return true
	end
	which_key_loaded = true

	if not lazy.packadd("which-key.nvim", { log = false, trigger = "key prefix" }) then
		which_key_loaded = false
		return false
	end

	local wk = lazy.require("which-key", { log = false })
	if not wk then
		which_key_loaded = false
		return false
	end

	local wk_icons = {
		search = "󰍉",
		buffer = "󰈔",
		file = "󰈔",
		code = "",
		lsp = "󰒋",
		paste = "󰅇",
		go_to = "󰁔",
		window = "",
		ui = "󰙵",
		editor = "󰙵",
		notification = "󰵅",
		exit = "󰈆",
		quit = "󰈆",
		brain = "🧠",
		bolt = "⚡",
	}
	wk.setup({
		preset = "helix",
		delay = 400,
		sort = { "order", "group", "alphanum", "mod" },
		plugins = { spelling = { enabled = false } },
		triggers = {
			{ "<auto>", mode = "nxso" },
			{ "[", mode = { "n", "x", "o" } },
			{ "]", mode = { "n", "x", "o" } },
		},
		icons = {
			rules = {
				-- Keep semantic object rules ahead of broad action rules so labels like
				-- "Find Files" and "Find Diagnostics" retain their specific icons.
				-- stylua: ignore start
				{ pattern = "buffer", icon = wk_icons.buffer, color = "cyan" },
				{ pattern = "debug", icon = "󰃤 ", color = "red" },
				{ pattern = "diagnostic", icon = "󱖫 ", color = "green" },
				{ pattern = "exit", icon = wk_icons.exit .. " ", color = "red" },
				{ pattern = "file", icon = wk_icons.file, color = "cyan" },
				{ pattern = "%f[%a]git", cat = "filetype", name = "git", color = "orange" },
				{ pattern = "go to", icon = wk_icons.go_to, color = "purple" },
				{ pattern = "grep", icon = wk_icons.search, color = "green" },
				{ pattern = "search", icon = wk_icons.search, color = "green" },
				{ pattern = "lazy", cat = "filetype", name = "lazy" },
				{ pattern = "navigate", icon = wk_icons.window, color = "blue" },
				{ pattern = "notif", icon = wk_icons.notification .. " ", color = "blue" },
				{ pattern = "profiler", icon = wk_icons.bolt, color = "orange" },
				{ pattern = "quit", icon = wk_icons.quit .. " ", color = "red" },
				{ pattern = "tab", icon = "󰓩 ", color = "purple" },
				{ pattern = "test", cat = "filetype", name = "neotest-summary" },
				{ pattern = "ui", icon = wk_icons.ui .. " ", color = "cyan" },
				{ pattern = "editor", icon = wk_icons.editor .. " ", color = "cyan" },

				{ plugin = "mini.diff", cat = "filetype", name = "git", color = "orange" },
				{ plugin = "obsidian.nvim", icon = wk_icons.brain },
				{ plugin = "neotest", cat = "filetype", name = "neotest-summary" },
				-- stylua: ignore end
			},
		},
		expand = 1,
		spec = {
			{
				mode = { "n", "x" },
				{ "<leader>a", group = "AI", icon = "🤖" },
				{
					"<leader>b",
					group = "Buffers",
					expand = function()
						return require("which-key.extras").expand.buf()
					end,
				},
				{ "<leader>c", group = "Code", icon = { icon = wk_icons.code, color = "orange" } },
				{ "<leader>d", group = "Debug" },
				{ "<leader>e", group = "Editor" },
				{ "<leader>f", group = "Find", icon = { icon = wk_icons.search, color = "green" } },
				{ "<leader>g", group = "Git" },
				{ "<leader>gh", group = "Hunks" },
				{ "<leader>go", group = "GitHub", icon = "󰊤" },
				{ "<leader>l", group = "LSP", icon = { icon = wk_icons.lsp, color = "orange" } },
				{ "<leader>m", group = "Markdown", icon = wk_icons.brain, mode = "n" },
				{ "<leader>p", group = "Paste", icon = { icon = wk_icons.paste, color = "yellow" }, mode = "n" },
				{ "<leader>t", group = "Tests" },
				{ "<leader>x", group = "Diagnostics & Lists" },
				{ "<leader><tab>", group = "Tabs" },
				{ "gr", group = "LSP", icon = { icon = wk_icons.lsp, color = "orange" } },
				{ "gO", desc = "Document Symbols", mode = "n" },
				{ "gra", desc = "Code Actions" },
				{ "gri", desc = "Go to Implementation", mode = "n" },
				{ "grn", desc = "Rename Symbol", mode = "n" },
				{ "grr", desc = "Find References", mode = "n" },
				{ "grt", desc = "Go to Type Definition", mode = "n" },
				{ "grx", desc = "Run Code Lens", mode = "n" },
			},
		},
	})
	return true
end

local function lazy_prefix_loader(prefix)
	return function()
		if not setup_which_key() then
			return
		end
		-- which-key schedules its trigger setup after setup(). Show on the next
		-- loop so the first prefix press still opens help after loading code.
		vim.schedule(function()
			local ok, wk = pcall(require, "which-key")
			if ok then
				pcall(wk.show, { keys = prefix })
			end
		end)
	end
end

for _, prefix in ipairs({
	{ lhs = "<leader>", mode = { "n", "x" } },
	{ lhs = "[", mode = { "n", "x", "o" } },
	{ lhs = "]", mode = { "n", "x", "o" } },
}) do
	local lhs = prefix.lhs
	vim.keymap.set(prefix.mode, lhs, lazy_prefix_loader(lhs), {
		silent = true,
		desc = "which-key-trigger lazy-load",
		-- Keep these mappings waitable: they are prefixes for real mappings.
		-- With nowait=true, a standalone prefix can win before fast sequences
		-- like <leader>fw or ]f are resolved.
	})
end
