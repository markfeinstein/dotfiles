local lazy = require("mark.lazy")
local ensure_codediff = lazy.setup_once("codediff.nvim", "codediff", function(codediff)
	codediff.setup({
		highlights = {
			-- Derive char-level highlight colours from the active theme's DiffAdd/DiffDelete
			-- fg at setup time. Fall back to a neutral mid-grey so the colours are at
			-- least readable on any background rather than hard-coding rose-pine values.
			char_insert = string.format("#%06x", vim.api.nvim_get_hl(0, { name = "DiffAdd" }).fg or 0x888888),
			char_delete = string.format("#%06x", vim.api.nvim_get_hl(0, { name = "DiffDelete" }).fg or 0x888888),
			char_brightness = 5,
		},
		diff = {
			ignore_trim_whitespace = true,
		},
	})
end, "git keymap")

-- mini.diff - Git Signs and Hunks
-- mini.diff is set up after startup in plugin/mini.lua.

-- Set up buffer-local keymaps after diff is computed
vim.api.nvim_create_autocmd("User", {
	group = vim.api.nvim_create_augroup("minidiff_keymaps"),
	pattern = "MiniDiffUpdated",
	callback = function(args)
		local bufnr = args.buf

		-- Only set keymaps once per buffer
		if vim.b[bufnr].minidiff_keymaps_set then
			return
		end
		vim.b[bufnr].minidiff_keymaps_set = true

		local function map(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buf = bufnr, desc = desc, silent = true })
		end

		local diff = require("mini.diff")

		local function do_current_hunk(action)
			local line = vim.api.nvim_win_get_cursor(0)[1]
			diff.do_hunks(bufnr, action, { line_start = line, line_end = line })
		end

		local function do_visual_hunks(action)
			local mode = vim.api.nvim_get_mode().mode
			local start_line = mode:match("[vV\22]") and vim.fn.line("v") or vim.fn.getpos("'<")[2]
			local end_line = mode:match("[vV\22]") and vim.fn.line(".") or vim.fn.getpos("'>")[2]
			if start_line > end_line then
				start_line, end_line = end_line, start_line
			end
			diff.do_hunks(bufnr, action, { line_start = start_line, line_end = end_line })
		end

		map("n", "<leader>ghs", function()
			do_current_hunk("apply")
		end, "Apply/Stage Hunk")
		map("x", "<leader>ghs", function()
			do_visual_hunks("apply")
		end, "Apply/Stage Hunk")

		map("n", "<leader>ghr", function()
			do_current_hunk("reset")
		end, "Reset Hunk")
		map("x", "<leader>ghr", function()
			do_visual_hunks("reset")
		end, "Reset Hunk")

		map("n", "<leader>gR", function()
			-- Reset entire buffer by applying reset to all lines
			local ok = vim.fn.confirm("Reset entire buffer to HEAD?", "&Yes\n&No", 2)
			if ok == 1 then
				local ok_reset = pcall(diff.do_hunks, bufnr, "reset", {
					line_start = 1,
					line_end = vim.api.nvim_buf_line_count(bufnr),
				})
				if ok_reset then
					vim.notify("Buffer reset to HEAD", vim.log.levels.INFO)
				else
					vim.notify("Failed to reset buffer to HEAD", vim.log.levels.ERROR)
				end
			end
		end, "Reset Buffer to HEAD")

		map("n", "<leader>ghp", function()
			diff.toggle_overlay()
		end, "Toggle Diff Overlay")

		-- Blame operations using Snacks
		map("n", "<leader>gb", function()
			require("snacks").git.blame_line()
		end, "Git Blame Line")

		-- Diff operations using CodeDiff
		map("n", "<leader>gd", function()
			if not ensure_codediff() then
				return
			end
			vim.cmd("CodeDiff file HEAD")
		end, "Diff Current File Against HEAD")
	end,
})

-- Neogit - Git UI

local neogit_opts = function()
	local neogit_icons = {
		neogit_expand = "󰬫",
		neogit_collapse = "󰬧",
	}
	return {
		floating = {
			width = 0.9,
			height = 0.9,
		},
		graph_style = "kitty",
		mappings = {
			status = {
				["[h"] = "GoToPreviousHunkHeader",
				["]h"] = "GoToNextHunkHeader",
			},
		},
		signs = {
			item = { neogit_icons.neogit_expand, neogit_icons.neogit_collapse },
			section = { "", "" },
		},
		status = { recent_commit_count = 40 },
		commit_editor = {
			kind = "floating",
			staged_diff_split_kind = "auto",
		},
		commit_view = { kind = "auto" },
		log_view = { kind = "auto" },
		popup = { kind = "floating" },
		stash = { kind = "floating" },
	}
end

local ensure_neogit = lazy.setup_once("neogit", "neogit", function(neogit)
	neogit.setup(neogit_opts())
end, "git keymap", ensure_codediff)

vim.api.nvim_create_autocmd("CmdUndefined", {
	pattern = "Neogit",
	callback = function()
		ensure_neogit("CmdUndefined Neogit")
	end,
	desc = "Lazy-load neogit.nvim for :Neogit",
})

vim.keymap.set("n", "<leader>gs", lazy.command(ensure_neogit, "Neogit"), { desc = "Open Git Status" })
vim.keymap.set("n", "<leader>gB", lazy.command(ensure_neogit, "Neogit log"), { desc = "View Git Log" })

-- Octo - GitHub Integration

local ensure_octo = lazy.setup_once({ "plenary.nvim", "fzf-lua", "octo.nvim" }, "octo", function(octo)
	octo.setup({
		picker = "fzf-lua",
		enable_builtin = true,
		use_local_fs = true,
		users = "assignable",
		poll = { enabled = true },
		issues = { order_by = { field = "UPDATED_AT" } },
		pull_requests = { order_by = { field = "UPDATED_AT" } },
		commands = {
			my_prs = {
				kind = "pr",
				args = { assignee = "@me", states = "OPEN" },
			},
			review_queue = {
				kind = "pr",
				args = { reviewer = "@me", states = "OPEN" },
			},
			pr_runs = {
				kind = "pr",
				cmd = "runs",
			},
		},
	})
end, "GitHub keymap")

vim.api.nvim_create_autocmd("CmdUndefined", {
	pattern = "Octo",
	callback = function()
		ensure_octo("CmdUndefined Octo")
	end,
	desc = "Lazy-load octo.nvim for :Octo",
})

vim.keymap.set("n", "<leader>goi", lazy.command(ensure_octo, "Octo issue list"), { desc = "List GitHub Issues" })
vim.keymap.set("n", "<leader>gop", lazy.command(ensure_octo, "Octo pr list"), { desc = "List GitHub Pull Requests" })
vim.keymap.set(
	"n",
	"<leader>goo",
	lazy.command(ensure_octo, "Octo actions"),
	{ desc = "Open Issue/Pull Request Actions" }
)
vim.keymap.set(
	"n",
	"<leader>goO",
	lazy.command(ensure_octo, "Octo pr edit"),
	{ desc = "Open Pull Request for Current Branch" }
)
vim.keymap.set("n", "<leader>gos", function()
	if not ensure_octo() then
		return
	end
	require("octo.utils").create_base_search_command({ include_current_repo = false })
end, { desc = "Search GitHub" })
vim.keymap.set(
	"n",
	"<leader>gon",
	lazy.command(ensure_octo, "Octo notification list"),
	{ desc = "List GitHub Notifications" }
)
vim.keymap.set(
	"n",
	"<leader>god",
	lazy.command(ensure_octo, "Octo discussion list"),
	{ desc = "List GitHub Discussions" }
)
vim.keymap.set("n", "<leader>goc", lazy.command(ensure_octo, "Octo issue create"), { desc = "Create GitHub Issue" })
vim.keymap.set(
	"n",
	"<leader>goP",
	lazy.command(ensure_octo, "Octo pr create draft"),
	{ desc = "Create Draft GitHub Pull Request" }
)
vim.keymap.set("n", "<leader>gor", lazy.command(ensure_octo, "Octo repo view"), { desc = "View GitHub Repository" })
vim.keymap.set("n", "<leader>gow", lazy.command(ensure_octo, "Octo run list"), { desc = "List GitHub Workflow Runs" })
