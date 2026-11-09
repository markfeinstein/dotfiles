local M = {}

function M.setup(context)
	local api = context.api
	local augroup = context.augroup
	local get_valid_ui2_buf = context.get_valid_ui2_buf
	local get_valid_ui2_win = context.get_valid_ui2_win
	local ui2 = context.ui2

	-- Command to dismiss Snacks notifications and any native UI2 message window.
	api.nvim_create_user_command("DismissMsg", function()
		local snacks = rawget(_G, "Snacks")
		if snacks and snacks.notifier then
			pcall(snacks.notifier.hide)
		end
		local win = get_valid_ui2_win(ui2.wins and ui2.wins.msg)
		if win then
			pcall(api.nvim_win_hide, win)
		end
	end, { desc = "Dismiss all floating notifications" })

	-- Pager window styling (:messages output)

	local function pager_title()
		local buf = get_valid_ui2_buf(ui2.bufs and ui2.bufs.pager)
		if not buf then
			return " Output "
		end

		local ok, lines = pcall(api.nvim_buf_get_lines, buf, 0, 5, false)
		if not ok or not lines then
			lines = {}
		end

		-- Heuristic detection based on first few lines.
		for _, line in ipairs(lines) do
			if line:match("^%s*%d+%s+[%%#]") then
				return " Buffers "
			elseif line:match("^%s*[a-z]%s+%d+%s+") then
				return " Marks "
			elseif line:match("^||") or line:match("^error:") or line:match("^warning:") then
				return " Quickfix "
			end
		end
		return " Output "
	end

	local function apply_pager_style()
		local win = get_valid_ui2_win(ui2.wins and ui2.wins.pager)
		if not win then
			return
		end

		pcall(api.nvim_win_set_config, win, {
			border = "rounded",
			title = pager_title(),
			title_pos = "center",
			footer = " q: close | j/k: scroll ",
			footer_pos = "center",
		})

		pcall(
			api.nvim_set_option_value,
			"winhighlight",
			"Normal:PagerPopup,FloatBorder:DiagnosticSignInfo,FloatTitle:DiagnosticSignInfo",
			{ win = win }
		)
	end

	local function schedule_pager_style()
		vim.schedule(apply_pager_style)
	end

	-- vim._core.ui2.messages.set_pos() and enter_pager() can rewrite the pager
	-- window border after FileType has fired. Reapply defensively after the private
	-- reposition path and after enter/resize events; only ui2.wins.pager is touched.
	do
		local msg_module = ui2.msg
		if type(msg_module) == "table" and type(msg_module.set_pos) == "function" then
			msg_module._mark_orig_set_pos = msg_module._mark_orig_set_pos or msg_module.set_pos
			local original_set_pos = msg_module._mark_orig_set_pos
			msg_module.set_pos = function(tgt, focus)
				original_set_pos(tgt, focus)
				if tgt == nil or tgt == "pager" then
					schedule_pager_style()
				end
			end
		end
	end

	api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = "pager",
		callback = apply_pager_style,
	})

	api.nvim_create_autocmd({ "WinEnter", "WinResized" }, {
		group = augroup,
		callback = schedule_pager_style,
	})
end

return M
