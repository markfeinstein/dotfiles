local M = {}

local snacks_opts = {
	gitbrowse = {
		notify = false,
		what = "permalink",
		remote_patterns = {
			{ "ssh://org[-]%d+@", "" },
		},
		open = function(url)
			vim.fn.setreg("+", url)
			require("snacks").notify("Copied URL")
		end,
	},
	image = {
		img_dirs = { "img", "images", "7 - Assets", "assets", "static", "public", "media", "attachments" },
	},
	indent = {
		indent = { only_current = true, only_scope = true },
	},
	notifier = { enabled = true },
	scope = {},
	styles = {
		zen = { width = 0.50 },
	},
}

function M.setup()
	-- Rex implements the Kitty graphics protocol, including Unicode placeholders.
	-- Snacks currently needs a terminal compatibility flag to enable image rendering.
	if vim.env.TERM_PROGRAM == "rex" and vim.env.SNACKS_GHOSTTY == nil then
		vim.env.SNACKS_GHOSTTY = "true"
	end

	local snacks = require("snacks")
	if not snacks.did_setup then
		snacks.setup(snacks_opts)
	end
	return snacks
end

return M
