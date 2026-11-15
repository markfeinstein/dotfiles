local M = {}

local state_key = "dotfiles_obsidian_autosave"

local function timer_is_closing(timer)
	local ok, closing = pcall(timer.is_closing, timer)
	return ok and closing
end

function M.stop()
	local state = rawget(_G, state_key)
	if not state then
		return
	end

	if state.timer then
		pcall(state.timer.stop, state.timer)
		if not timer_is_closing(state.timer) then
			pcall(state.timer.close, state.timer)
		end
	end

	rawset(_G, state_key, nil)
end

function M.is_eligible(bufnr, is_vault_path)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return false
	end

	local options = vim.bo[bufnr]
	if
		not options.modified
		or not options.modifiable
		or options.readonly
		or options.buftype ~= ""
		or options.filetype ~= "markdown"
	then
		return false
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	return path ~= "" and is_vault_path(path)
end

local function write_buffer(bufnr, current_bufnr)
	local write = function()
		vim.cmd("silent keepjumps update")
	end

	if bufnr == current_bufnr then
		return pcall(write)
	end
	return pcall(vim.api.nvim_buf_call, bufnr, write)
end

function M.save_modified_buffers(opts)
	local is_vault_path = assert(opts.is_vault_path, "is_vault_path is required")
	local current_win = vim.api.nvim_get_current_win()
	local current_bufnr = vim.api.nvim_get_current_buf()
	local view
	if vim.api.nvim_win_is_valid(current_win) then
		view = vim.api.nvim_win_call(current_win, vim.fn.winsaveview)
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if M.is_eligible(bufnr, is_vault_path) then
			local ok, err = write_buffer(bufnr, current_bufnr)
			if not ok then
				vim.notify(
					("Failed to auto-save Obsidian note %s: %s"):format(vim.api.nvim_buf_get_name(bufnr), err),
					vim.log.levels.ERROR
				)
			end
		end
	end

	if view and vim.api.nvim_win_is_valid(current_win) and vim.api.nvim_win_get_buf(current_win) == current_bufnr then
		vim.api.nvim_win_call(current_win, function()
			vim.fn.winrestview(view)
		end)
	end
end

function M.setup(opts)
	M.stop()

	local group = vim.api.nvim_create_augroup("dotfiles_obsidian_autosave", { clear = true })
	if not opts.enabled then
		return nil
	end

	local interval_ms = assert(opts.interval_ms, "interval_ms is required")
	assert(interval_ms > 0, "interval_ms must be positive")
	local is_vault_path = assert(opts.is_vault_path, "is_vault_path is required")
	local timer = assert(vim.uv.new_timer(), "failed to create Obsidian auto-save timer")
	local state = { timer = timer }
	rawset(_G, state_key, state)

	timer:start(
		interval_ms,
		interval_ms,
		vim.schedule_wrap(function()
			if rawget(_G, state_key) == state then
				M.save_modified_buffers({ is_vault_path = is_vault_path })
			end
		end)
	)

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = M.stop,
		desc = "Stop the Obsidian auto-save timer",
	})

	return timer
end

return M
