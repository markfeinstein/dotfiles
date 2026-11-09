local map = vim.keymap.set

-- Table-driven keymap registration keeps related mappings compact.
-- stylua: ignore start
local keymaps = {
  -- Center cursor vertically when moving by half-pages
  { "n", "<C-d>", "<C-d>zzzv", { desc = "Scroll Half-Page Down", silent = true } },
  { "n", "<C-u>", "<C-u>zzzv", { desc = "Scroll Half-Page Up", silent = true } },

  -- https://github.com/mhinz/vim-galore#saner-behavior-of-n-and-n
  { { "n", "x", "o" }, "n", "'Nn'[v:searchforward].'zzzv'", { expr = true, desc = "Next Search Result" } },
  { { "n", "x", "o" }, "N", "'nN'[v:searchforward].'zzzv'", { expr = true, desc = "Previous Search Result" } },

  -- better indenting
  { "x", "<", "<gv", { desc = "Indent Left" } },
  { "x", ">", ">gv", { desc = "Indent Right" } },

  -- Terminal Mappings
  { "t", "<C-/>", "<cmd>close<cr>", { desc = "Close Terminal" } },
  { "t", "<c-_>", "<cmd>close<cr>", { desc = "which_key_ignore" } },

  -- tabs
  { "n", "<leader><tab><tab>", "<cmd>tabnew<cr>", { desc = "New Tab", silent = true } },
  { "n", "<leader><tab>d", "<cmd>tabclose<cr>", { desc = "Close Tab", silent = true } },
  { "n", "<leader><tab>f", "<cmd>tabfirst<cr>", { desc = "First Tab", silent = true } },
  { "n", "<leader><tab>l", "<cmd>tablast<cr>", { desc = "Last Tab", silent = true } },
  { "n", "<leader><tab>o", "<cmd>tabonly<cr>", { desc = "Close Other Tabs", silent = true } },
  { "n", "[<tab>", "<cmd>tabprevious<cr>", { desc = "Previous Tab", silent = true } },
  { "n", "]<tab>", "<cmd>tabnext<cr>", { desc = "Next Tab", silent = true } },

  -- Custom register behavior
  { { "n", "v" }, "c", '"cc', { silent = true, desc = "Change (to register c)" } },
  { { "n", "v" }, "d", '"dd', { silent = true, desc = "Delete (to register d)" } },
  { "x", "p", '"_dP', { silent = true, desc = "Paste without overwriting default register" } },

  -- Paste with auto-indent (Neovim 0.12+)
  -- :iput works like :put but adjusts indentation to match current context
  { "n", "<leader>pi", "<cmd>iput<cr>", { desc = "Paste Below with Indent", silent = true } },
  { "n", "<leader>pI", "<cmd>iput!<cr>", { desc = "Paste Above with Indent", silent = true } },

  -- Other mappings
  { "n", "<leader>ei", "<cmd>Inspect<cr>", { desc = "Inspect Position", silent = true } },
  { "n", "<leader>`", "<cmd>e #<cr>", { desc = "Switch to Alternate Buffer", silent = true } },
  { "n", "<leader>cH", "<cmd>checkhealth vim.lsp<cr>", { desc = "LSP Health", silent = true } },
  { "n", "<D-f>", "/", { desc = "Search" } },
}
-- stylua: ignore end

local neotest_ui_filetypes = {
	["neotest-output"] = true,
	["neotest-output-panel"] = true,
	["neotest-summary"] = true,
}

local neotest_exit_check_pending = false

local function is_empty_placeholder(buf)
	return vim.api.nvim_buf_get_name(buf) == ""
		and vim.bo[buf].buftype == ""
		and not vim.bo[buf].modified
		and vim.api.nvim_buf_line_count(buf) == 1
		and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function queue_neotest_exit_check()
	if neotest_exit_check_pending then
		return
	end
	neotest_exit_check_pending = true
	vim.schedule(function()
		neotest_exit_check_pending = false

		local found_neotest_window = false
		for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
				local config = vim.api.nvim_win_get_config(win)
				local buf = vim.api.nvim_win_get_buf(win)
				local filetype = vim.bo[buf].filetype
				if neotest_ui_filetypes[filetype] then
					found_neotest_window = true
				elseif config.relative == "" and not is_empty_placeholder(buf) then
					return
				end
			end
		end

		if found_neotest_window then
			vim.cmd("quitall")
		end
	end)
end

local close_ui_group = vim.api.nvim_create_augroup("close_ui_buffers", { clear = true })

-- Close some filetypes with <q>.
-- Lives in after/plugin/ so our keymap runs AFTER plugin FileType handlers
-- (oil, neotest, dap-view, etc. register their own q keymaps in plugin/).
vim.api.nvim_create_autocmd("FileType", {
	group = close_ui_group,
	pattern = {
		"PlenaryTestPopup",
		"dap-repl",
		"dap-view",
		"help",
		"neotest-output",
		"neotest-output-panel",
		"neotest-summary",
		"qf",
	},
	callback = function(ev)
		vim.bo[ev.buf].buflisted = false
		queue_neotest_exit_check()
		vim.keymap.set("n", "q", function()
			pcall(vim.api.nvim_win_close, 0, false)
			pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
		end, {
			buf = ev.buf,
			silent = true,
			desc = "Quit buffer",
		})
	end,
})

vim.api.nvim_create_autocmd({ "BufDelete", "BufEnter", "BufWipeout", "WinClosed", "WinEnter" }, {
	group = close_ui_group,
	callback = queue_neotest_exit_check,
	desc = "Exit when only Neotest UI buffers remain",
})

-- <Esc> keymap is in plugin/ui/search.lua (owns NohlClear command + ui2 integration)

-- remap: `I` must reach the tree buffer's language-display toggle.
map("n", "<leader>eI", "<cmd>InspectTree<cr>I", { desc = "Inspect Tree", remap = true, silent = true })

map("n", "<leader>u", function()
	vim.cmd.packadd("nvim.undotree")
	vim.cmd.Undotree()
end, { desc = "Undo Tree", silent = true })

-- Batch register all keymaps
for _, km in ipairs(keymaps) do
	map(km[1], km[2], km[3], km[4])
end
