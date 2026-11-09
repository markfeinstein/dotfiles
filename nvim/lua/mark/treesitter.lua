local M = {}
local bigfile = require("mark.bigfile")
local lazy = require("mark.lazy")

vim.g.treesitter_max_file_size = vim.g.treesitter_max_file_size or 100000

local runtime_loaded = false

local language_aliases = {
	-- Neovim detects *.bats natively, but nvim-treesitter has no separate
	-- parser. Bats follows Bash syntax, so reuse the managed Bash grammar.
	bats = "bash",
}

function M.ensure_runtime()
	if runtime_loaded then
		return true
	end
	-- Keep parser lookup working if Nix moves nvim-treesitter-related packages
	-- from start to opt. Grammars are a separate Home Manager pack entry.
	local ok, failed, err = lazy.packadd_all(
		{ "nvim-treesitter-grammars", "nvim-treesitter" },
		{ trigger = "FileType" }
	)
	if not ok then
		return false, err or ("failed to packadd " .. failed)
	end
	runtime_loaded = true
	return true
end

function M.language_for(filetype)
	local lang = vim.treesitter.language.get_lang(filetype)
	local alias = language_aliases[filetype]
	if alias and lang == filetype then
		vim.treesitter.language.register(alias, filetype)
		return alias
	end
	return lang
end

function M.parser_available(filetype)
	-- nvim-treesitter registers aliases such as sh -> bash when it loads.
	if not M.ensure_runtime() then
		return false
	end
	local lang_ok, lang = pcall(M.language_for, filetype)
	if not lang_ok or not lang then
		return false
	end

	local add_ok, available = pcall(vim.treesitter.language.add, lang)
	return add_ok and available == true
end

function M.disabled_for_buffer(buf)
	if vim.bo[buf].buftype ~= "" then
		return true
	end

	if vim.bo[buf].filetype == "bigfile" then
		return true
	end

	local path = vim.api.nvim_buf_get_name(buf)
	local size = bigfile.buffer_file_size(buf, path)
	return size ~= nil and size > vim.g.treesitter_max_file_size
end

function M.has_folds(buf)
	if M.disabled_for_buffer(buf) then
		return false
	end

	local ft = vim.bo[buf].filetype
	if ft == "" then
		return false
	end

	return M.parser_available(ft)
end

local fold_bufs = {}
vim.api.nvim_create_autocmd("BufWipeout", {
	group = vim.api.nvim_create_augroup("treesitter_fold_state"),
	callback = function(ev)
		fold_bufs[ev.buf] = nil
	end,
})

--- Global 'foldexpr': Tree-sitter folds where FileType enabled them (see
--- M.update_folds), no folds elsewhere. Gating here keeps foldexpr from
--- parsing buffers that disabled_for_buffer() excludes.
function M.foldexpr()
	if fold_bufs[vim.api.nvim_get_current_buf()] then
		return vim.treesitter.foldexpr()
	end
	return "0"
end

function M.folds_enabled(buf)
	return fold_bufs[buf == 0 and vim.api.nvim_get_current_buf() or buf] == true
end

function M.update_folds(buf)
	local enabled = M.has_folds(buf) or nil
	if fold_bufs[buf] == enabled then
		return
	end
	fold_bufs[buf] = enabled
	-- Recompute folds in windows that already evaluated the old gate.
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if vim.wo[win].foldexpr == M.foldexpr then
			vim.wo[win][0].foldexpr = M.foldexpr
		end
	end
end

return M
