vim.g.mapleader = " "

local shell_name = vim.fs.basename(vim.o.shell)
if shell_name == "zsh" and vim.o.shellcmdflag == "-c" then
	-- Neovim's Nix wrapper prepends runtime tools (including fd) to PATH, but
	-- zsh startup files can replace PATH for noninteractive string commands.
	-- Keep the user's shell and only skip startup files for the default zsh -c path.
	vim.o.shellcmdflag = "-f -c"
end

vim.o.mouse = "a"
-- Append limits so the default r/tmp/ and r/private/ exclusions survive.
vim.opt.shada:append({ ":500", "/100", "@100" })
-- Plugins are Nix-managed; keep experimental vim.pack state out of this checkout.
vim.o.packlockfile = vim.fs.joinpath(vim.fn.stdpath("state"), "nvim-pack-lock.json")
vim.o.switchbuf = "usetab"
vim.o.undofile = true
vim.o.undolevels = 10000

-- UI
vim.o.breakindent = true
vim.o.breakindentopt = "list:-1"
vim.o.colorcolumn = "+1"
vim.o.cursorline = true
vim.o.linebreak = true
vim.o.list = true
vim.o.number = true
vim.o.relativenumber = true
vim.o.pumheight = 10
vim.o.pummaxwidth = 100

vim.o.ruler = false
vim.o.report = 1
vim.o.shortmess = "ICFOWacsS"
vim.o.showmode = false
vim.o.signcolumn = "yes"
vim.o.splitbelow = true
vim.o.splitkeep = "screen"
vim.o.splitright = true
vim.o.wrap = false -- Don't visually wrap lines (toggle with <leader>ew)
vim.o.cmdheight = 0 -- don't show command line, handled by vim._core.ui2
-- UI2 already defaults maxheight to 50 and timeout to 4000; pager:<CR> restores
-- the pre-0.13 key for opening collapsed output.
vim.o.messagesopt = "history:100,hit-enter,pager:<CR>,progress:c"
vim.o.formatlistpat = [[^\s*[0-9\-\+\*]\+[\.\)]*\s\+]] -- Pattern for detecting the start of a list item.
vim.o.clipboard = "unnamedplus"
vim.o.autowrite = true
vim.o.conceallevel = 2
vim.o.confirm = true
vim.o.grepprg = "rg --vimgrep"
vim.o.ignorecase = true
vim.o.inccommand = "split"
vim.opt.jumpoptions:append({ "view", "stack" }) -- Keep the default "clean"
vim.o.scrolloff = 4
vim.o.shiftround = true
vim.o.shiftwidth = 0 -- Follow 'tabstop' unless a filetype sets its own width
vim.o.smartcase = true
vim.o.tabstop = 2
vim.o.smartindent = true
vim.o.smoothscroll = true
vim.o.timeoutlen = 400
vim.o.updatetime = 500
vim.o.virtualedit = "block"
vim.o.pumborder = "rounded"
vim.o.winborder = "rounded"
vim.o.previewpopup = "height:12,width:80"
vim.o.swapfile = false

-- Hide the statusline only while a startup file is being read. Showing it
-- earlier can expose a provisional full path; an empty startup stays visible.
vim.o.laststatus = #vim.v.argf == 0 and 3 or 0

vim.opt.listchars = { tab = "  ", trail = " ", nbsp = "␣" }

-- Folding
vim.opt.fillchars = {
	-- Blank the end-of-buffer column; `~` markers over a transparent background
	-- read as content instead of padding.
	eob = " ",
	fold = " ",
	foldopen = icons.folds.open,
	foldclose = icons.folds.close,
	foldsep = " ",
	foldinner = icons.folds.inner,
}

local function foldtext()
	local line = vim.api.nvim_buf_get_lines(0, vim.v.foldstart - 1, vim.v.foldstart, false)[1] or ""
	return string.format("%s %s %d ", line, icons.folds.count, vim.v.foldend - vim.v.foldstart)
end

vim.o.foldcolumn = "1"
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
vim.o.foldtext = foldtext

local treesitter = require("mark.treesitter")
vim.o.foldmethod = "expr"
vim.o.foldexpr = treesitter.foldexpr

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("treesitter_folds"),
	callback = function(ev)
		treesitter.update_folds(ev.buf)
	end,
})
