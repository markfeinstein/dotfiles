-- Icons are needed on the first visible frame when files are passed.
now_if_args(function()
	require("mini.icons").setup()
	MiniIcons.mock_nvim_web_devicons()
end)

-- Diff signs and editing helpers are not needed for the first frame. Their
-- setup attaches to buffers that already exist when it runs.
later(function()
	require("mini.diff").setup({
		mappings = {
			apply = "",
			reset = "",
			textobject = "",
		},
		options = { wrap_goto = true },
		view = {
			style = "sign",
			signs = {
				add = icons.git.added,
				change = icons.git.modified,
				delete = icons.git.removed,
			},
		},
	})

	local hipatterns = require("mini.hipatterns")
	hipatterns.setup({
		highlighters = {
			fixme = { pattern = "%f[%w]()FIXME()%f[%W]", group = "MiniHipatternsFixme" },
			hack = { pattern = "%f[%w]()HACK()%f[%W]", group = "MiniHipatternsHack" },
			todo = { pattern = "%f[%w]()TODO()%f[%W]", group = "MiniHipatternsTodo" },
			note = { pattern = "%f[%w]()NOTE()%f[%W]", group = "MiniHipatternsNote" },
			hex_color = hipatterns.gen_highlighter.hex_color(),
		},
	})

	require("mini.ai").setup({ silent = true })
	require("mini.move").setup({ mappings = { down = "J", up = "K" } })
	local splitjoin = require("mini.splitjoin")
	splitjoin.setup({ mappings = { toggle = "<leader>j" } })
	-- Keep mini.splitjoin's operator behavior while exposing the user-facing action.
	vim.keymap.set("n", "<leader>j", function()
		return splitjoin.operator("toggle") .. " "
	end, { desc = "Toggle Split/Join", expr = true, silent = true })
	vim.keymap.set(
		"x",
		"<leader>j",
		":<C-u>lua MiniSplitjoin.toggle({ region = MiniSplitjoin.get_visual_region() })<CR>",
		{ desc = "Toggle Split/Join", silent = true }
	)
	require("mini.surround").setup()
end)
