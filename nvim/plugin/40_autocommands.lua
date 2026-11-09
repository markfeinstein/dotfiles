local lazy = require("mark.lazy")

local function path_is_uri(path)
	return vim.uri.parse(path) ~= nil
end

-- One shared augroup keeps :source idempotent.
local sync_group = vim.api.nvim_create_augroup("autocommands_sync")

-- Highlight on yank/paste
vim.api.nvim_create_autocmd({ "TextYankPost", "TextPutPost" }, {
	group = sync_group,
	callback = function()
		vim.hl.hl_op({ higroup = "Visual", timeout = 200 })
	end,
})

-- go to last loc when opening a buffer
vim.api.nvim_create_autocmd("BufReadPost", {
	group = sync_group,
	callback = function(event)
		local buf = event.buf
		if vim.bo[buf].filetype == "gitcommit" or vim.b[buf].last_loc then
			return
		end
		vim.b[buf].last_loc = true
		local mark = vim.api.nvim_buf_get_mark(buf, '"')
		local lcount = vim.api.nvim_buf_line_count(buf)
		if mark[1] > 0 and mark[1] <= lcount then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

-- :checkhealth collects healthchecks from 'runtimepath' before it opens its
-- buffer, so load the optional plugins that ship checks as soon as a
-- :checkhealth command line is submitted.
vim.api.nvim_create_autocmd("CmdlineLeave", {
	group = sync_group,
	pattern = ":",
	callback = function()
		if vim.v.event.abort then
			return
		end
		local ok, cmd = pcall(vim.api.nvim_parse_cmd, vim.fn.getcmdline())
		if not ok or cmd.cmd ~= "checkhealth" then
			return
		end
		for _, name in ipairs({ "nvim-treesitter", "obsidian.nvim" }) do
			lazy.packadd(name, { trigger = ":checkhealth" })
		end
		return true
	end,
})

-- These handlers must be registered before startup buffers emit FileType.
-- :checkhealth creates a listed buffer; its built-in q mapping closes it.
vim.api.nvim_create_autocmd("FileType", {
	group = sync_group,
	pattern = { "man", "checkhealth" },
	callback = function(event)
		vim.bo[event.buf].buflisted = false
	end,
})

local function set_english_spell(buf, win)
	vim.bo[buf].spelllang = "en"
	vim.bo[buf].spelloptions = "camel"
	vim.wo[win][0].spell = true
end

-- Wrap text-like buffers immediately, then enable spell after the first paint.
vim.api.nvim_create_autocmd("FileType", {
	group = sync_group,
	pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
	callback = function(event)
		local win = event.win
		if not win or win == 0 or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= event.buf then
			return
		end

		vim.wo[win][0].wrap = true
		later(function()
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == event.buf then
				set_english_spell(event.buf, win)
			end
		end)
	end,
})

-- Auto create dir when saving a file, in case some intermediate directory does not exist
vim.api.nvim_create_autocmd("BufWritePre", {
	group = sync_group,
	callback = function(event)
		if vim.bo[event.buf].buftype ~= "" then
			return
		end -- Skip non-file buffers
		if path_is_uri(event.match) then
			return
		end
		local file = vim.uv.fs_realpath(event.match) or event.match
		vim.fs.mkdir(vim.fn.fnamemodify(file, ":p:h"), { parents = true })
	end,
})

-- Resize splits if window got resized.
vim.api.nvim_create_autocmd("VimResized", {
	group = sync_group,
	callback = function()
		local current_tab = vim.fn.tabpagenr()
		vim.cmd("tabdo wincmd =")
		vim.cmd("tabnext " .. current_tab)
	end,
})
