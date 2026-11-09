-- Octo buffer-local settings and keymaps
-- Loaded automatically when FileType octo is triggered

local set = vim.opt_local

-- Enable spell check and text wrapping in octo buffers
set.spell = true
set.wrap = true
set.linebreak = true

-- Add buffer-local keymap to show actions
vim.keymap.set("n", "?", "<CMD>Octo actions<CR>", {
	buf = 0,
	desc = "Show Octo actions",
	silent = true,
})

-- @mention and #issue completion handled by blink.cmp (per_filetype sources)

-- Register markdown treesitter for octo buffers.
vim.treesitter.language.register("markdown", "octo")
