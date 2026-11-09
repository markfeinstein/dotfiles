local M = {}

function M.close_on_focus_loss(ctx)
	local group_name = "fzf_lua_focus_" .. ctx.bufnr
	local group = vim.api.nvim_create_augroup(group_name)
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			vim.schedule(function()
				local picker = require("fzf-lua").utils.fzf_winobj()
				if not picker or picker.fzf_bufnr ~= ctx.bufnr then
					pcall(vim.api.nvim_del_augroup_by_name, group_name)
					return
				end
				local current = vim.api.nvim_get_current_win()
				if current == picker.fzf_winid or current == picker.preview_winid then
					return
				end
				pcall(require("fzf-lua").win.close, ctx.bufnr)
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		buf = ctx.bufnr,
		once = true,
		callback = function()
			pcall(vim.api.nvim_del_augroup_by_name, group_name)
		end,
	})
end

function M.on_create(callback)
	return function(ctx)
		if callback then
			callback(ctx)
		end
		M.close_on_focus_loss(ctx)
	end
end

return M
