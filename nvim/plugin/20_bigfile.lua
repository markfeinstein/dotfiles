-- Detect and handle big files by disabling expensive features

local bigfile = require("mark.bigfile")

local group = vim.api.nvim_create_augroup("bigfile")

local function clear_matchparen(buf)
	local ok, matchparen = pcall(require, "nvim.matchparen")
	if not ok or type(matchparen.remove_matches) ~= "function" then
		return
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		pcall(matchparen.remove_matches, win)
	end
end

local function is_bigfile_buffer(buf)
	return vim.api.nvim_buf_is_valid(buf) and (vim.bo[buf].filetype == "bigfile" or vim.b[buf].bigfile_applied == true)
end

local function apply_bigfile_window_options(buf, win)
	if not is_bigfile_buffer(buf) or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end

	for k, v in pairs({ foldmethod = "manual", statuscolumn = "", conceallevel = 0 }) do
		vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
	end
end

local function apply_bigfile_display_options(buf)
	if not is_bigfile_buffer(buf) then
		return
	end

	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		apply_bigfile_window_options(buf, win)
	end
end

local function disable_minidiff(buf)
	vim.b[buf].minidiff_disable = true
	local minidiff = package.loaded["mini.diff"]
	if minidiff and type(minidiff.disable) == "function" then
		pcall(minidiff.disable, buf)
	end
end

local function apply_bigfile(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	vim.b[buf].bigfile_lsp_disabled = true
	disable_minidiff(buf)
	apply_bigfile_display_options(buf)
	-- Matchparen has documented buffer-local timeouts but no per-buffer enable
	-- switch. Bound its work without wrapping Neovim's internal implementation.
	vim.b[buf].matchparen_timeout = 1
	vim.b[buf].matchparen_insert_timeout = 1
	clear_matchparen(buf)
	pcall(vim.treesitter.stop, buf)

	-- A buffer can cross the threshold after LSP clients have already attached.
	-- Detach it without stopping clients that still serve other buffers.
	local lsp = package.loaded["vim.lsp"]
	if lsp then
		for _, client in ipairs(lsp.get_clients({ bufnr = buf })) do
			pcall(lsp.buf_detach_client, buf, client.id)
		end
	end

	if vim.b[buf].bigfile_applied then
		return
	end
	vim.b[buf].bigfile_applied = true

	local display_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p:~:.")
	vim.notify(("Big file detected `%s`. Some features have been disabled."):format(display_path), vim.log.levels.WARN)

	vim.b[buf].completion = false
	vim.b[buf].minihipatterns_disable = true

	-- Re-apply syntax after filetype pipeline completes when the minified-file
	-- path detected an original filetype before switching to bigfile.
	local ft = vim.b[buf].bigfile_original_filetype or ""
	if ft ~= "" then
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].syntax = ft
			end
		end)
	end
end

local function mark_bigfile(buf, original_ft)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if vim.bo[buf].filetype ~= "bigfile" then
		vim.b[buf].bigfile_original_filetype = original_ft or vim.bo[buf].filetype
		vim.bo[buf].filetype = "bigfile"
	end
	apply_bigfile(buf)
end

local function detect_bigfile(buf, path, original_ft)
	if not vim.api.nvim_buf_is_valid(buf) or not bigfile.should_mark(buf, path) then
		return false
	end

	local ft = original_ft or vim.bo[buf].filetype
	if ft == "" then
		ft = vim.filetype.match({ filename = path, buf = buf }) or ""
	end
	mark_bigfile(buf, ft)
	return true
end

-- Filetype detection is the only reliable way to stop large-file ftplugins from
-- running. Keep this catch-all path deliberately cheap: one fs_stat, no realpath,
-- and no line-count check.
vim.filetype.add({
	pattern = {
		[".*"] = {
			function(path, buf)
				if
					not path
					or path == ""
					or not buf
					or not vim.api.nvim_buf_is_valid(buf)
					or vim.bo[buf].filetype == "bigfile"
					or bigfile.is_snacks_image(path)
				then
					return
				end

				local size = bigfile.buffer_file_size(buf, path)
				if size and size > bigfile.size_threshold then
					vim.b[buf].bigfile_size = size
					vim.b[buf].bigfile_lsp_disabled = true
					return "bigfile"
				end
			end,
		},
	},
})

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	callback = function(ev)
		local path = vim.api.nvim_buf_get_name(ev.buf)
		local ft = ev.match ~= "bigfile" and ev.match or vim.bo[ev.buf].filetype
		detect_bigfile(ev.buf, path, ft)
	end,
	desc = "Detect large or minified buffers before LSP FileType setup",
})

vim.api.nvim_create_autocmd("BufReadPost", {
	group = group,
	callback = function(ev)
		local path = ev.file ~= "" and ev.file or vim.api.nvim_buf_get_name(ev.buf)
		if vim.b[ev.buf].bigfile_read_completed then
			bigfile.clear_buffer_size(ev.buf)
		end
		vim.b[ev.buf].bigfile_read_completed = true
		detect_bigfile(ev.buf, path)
	end,
	desc = "Detect small minified files after reading",
})

vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost" }, {
	group = group,
	callback = function(ev)
		if not vim.api.nvim_buf_is_valid(ev.buf) or vim.bo[ev.buf].filetype == "bigfile" then
			return
		end
		-- Re-stat explicitly so correctness does not depend on autocmd ordering
		-- with mark.bigfile's shared size-cache invalidator.
		bigfile.clear_buffer_size(ev.buf)
		local path = vim.api.nvim_buf_get_name(ev.buf)
		detect_bigfile(ev.buf, path)
	end,
	desc = "Guard buffers that grow into big files after opening",
})

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = "bigfile",
	callback = function(ev)
		apply_bigfile(ev.buf)
	end,
})

-- Matchparen has no documented per-buffer disable switch. Its native handler
-- runs on cursor movement, so clear only the matches it owns after that event.
vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
	group = group,
	callback = function(ev)
		if not is_bigfile_buffer(ev.buf) then
			return
		end
		vim.schedule(function()
			if is_bigfile_buffer(ev.buf) then
				clear_matchparen(ev.buf)
			end
		end)
	end,
	desc = "Clear native matchparen highlights in big files",
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
	group = group,
	callback = function(ev)
		local win = ev.win
		if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then
			return
		end
		local buf = vim.api.nvim_win_get_buf(win)
		if ev.buf and ev.buf ~= 0 and buf ~= ev.buf then
			return
		end
		apply_bigfile_window_options(buf, win)
	end,
	desc = "Apply bigfile window options whenever a bigfile buffer is displayed",
})
