local M = {}

M.size_threshold = 1.5 * 1024 * 1024 -- 1.5 MiB
M.line_length_threshold = 1000 -- average bytes per line (catches minified files)

function M.file_size(path)
	if not path or path == "" then
		return nil
	end
	local stat = vim.uv.fs_stat(path)
	return stat and stat.size or nil
end

function M.clear_buffer_size(buf)
	buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.b[buf].bigfile_size = nil
		vim.b[buf].bigfile_size_path = nil
	end
end

function M.buffer_file_size(buf, path)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end
	if not path or path == "" then
		vim.b[buf].bigfile_size = nil
		vim.b[buf].bigfile_size_path = nil
		return nil
	end

	if vim.b[buf].bigfile_size_path == path and vim.b[buf].bigfile_size ~= nil then
		return vim.b[buf].bigfile_size
	end

	if vim.b[buf].bigfile_size_path ~= path then
		vim.b[buf].bigfile_size = nil
		vim.b[buf].bigfile_size_path = nil
	end

	local size = M.file_size(path)
	if size == nil then
		vim.b[buf].bigfile_size = nil
		vim.b[buf].bigfile_size_path = nil
		return nil
	end

	vim.b[buf].bigfile_size = size
	vim.b[buf].bigfile_size_path = path
	return size
end

-- Keep initial FileType -> BufReadPost reuse intact: clearing on BufReadPost
-- would reintroduce duplicate startup stats. BufFilePost does not need its own
-- clear because buffer_file_size() qualifies the cache by the current path.
vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost" }, {
	group = vim.api.nvim_create_augroup("bigfile_size_cache"),
	callback = function(ev)
		M.clear_buffer_size(ev.buf)
	end,
	desc = "Invalidate cached buffer file size after same-path file changes",
})

function M.is_guarded(buf)
	return vim.b[buf].bigfile_lsp_disabled == true or vim.bo[buf].filetype == "bigfile"
end

function M.is_snacks_image(path)
	if not path or path == "" then
		return false
	end
	local snacks = rawget(_G, "Snacks")
	local image = snacks and snacks.config and snacks.config.image
	if not image or image.enabled ~= true then
		return false
	end
	local extension = vim.fn.fnamemodify(path, ":e"):lower()
	return extension ~= "" and vim.tbl_contains(image.formats or {}, extension)
end

function M.should_mark(buf, path)
	if not buf or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
		return false
	end
	if vim.bo[buf].filetype == "bigfile" or M.is_snacks_image(path) then
		return false
	end

	local size = M.buffer_file_size(buf, path)
	if not size or size <= 0 then
		return false
	end
	if size > M.size_threshold then
		return true
	end

	local lines = vim.api.nvim_buf_line_count(buf)
	if lines > 0 and (size - lines) / lines > M.line_length_threshold then
		return true
	end
	return false
end

return M
