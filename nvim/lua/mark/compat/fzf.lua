local M = {}

-- fzf-lua computes picker help immediately inside core.fzf_wrap and exposes no
-- public hook between that computation and window creation. Preserve the border
-- footer UI in one isolated compatibility adapter while composing the public
-- winopts.on_create callback used for focus handling.
function M.install_footer_headers()
	local core = require("fzf-lua.core")
	if core._mark_footer_headers then
		return
	end

	local original_fzf_wrap = core.fzf_wrap
	core.fzf_wrap = function(command, opts, ...)
		opts = opts or {}
		core.set_header(opts)
		local header = type(opts.header) == "string" and opts.header or opts.fzf_opts and opts.fzf_opts["--header"]
		if type(header) == "string" and header ~= "" and not (opts.winopts and opts.winopts.split) then
			local footer = {
				{ " " .. require("fzf-lua.utils").strip_ansi_coloring(header) .. " ", "FzfLuaBorder" },
			}
			opts.winopts = opts.winopts or {}
			local on_create = opts.winopts.on_create
			opts.winopts.on_create = function(ctx)
				if on_create then
					on_create(ctx)
				end
				if vim.api.nvim_win_is_valid(ctx.winid) then
					local config = vim.api.nvim_win_get_config(ctx.winid)
					if config.relative ~= "" then
						vim.api.nvim_win_set_config(ctx.winid, { footer = footer, footer_pos = "center" })
					end
				end
			end
			opts.header = nil
			opts.headers = false
			opts.fzf_opts = opts.fzf_opts or {}
			opts.fzf_opts["--header"] = nil
		end
		return original_fzf_wrap(command, opts, ...)
	end
	core._mark_footer_headers = true
end

-- fzf-lua 0.0.2756 can try to install an invalid preview buffer after rapid
-- picker changes. There is no public validation hook, so keep the compatibility
-- guard isolated and removable when upstream validates these handles.
function M.install_preview_guards()
	local builtin = require("fzf-lua.previewer.builtin")
	if not builtin.base._mark_valid_buffer_guard then
		local set_preview_buf = builtin.base.set_preview_buf
		builtin.base.set_preview_buf = function(self, newbuf, ...)
			if not newbuf or not vim.api.nvim_buf_is_valid(newbuf) then
				if self.preview_bufnr == newbuf then
					self.preview_bufnr = nil
				end
				return
			end
			return set_preview_buf(self, newbuf, ...)
		end

		local update_render_markdown = builtin.base.update_render_markdown
		builtin.base.update_render_markdown = function(self, ...)
			if not self.preview_bufnr or not vim.api.nvim_buf_is_valid(self.preview_bufnr) then
				self.preview_bufnr = nil
				return
			end
			return update_render_markdown(self, ...)
		end
		builtin.base._mark_valid_buffer_guard = true
	end

	local utils = require("fzf-lua.utils")
	if not utils._mark_valid_buffer_guard then
		local win_set_buf_noautocmd = utils.win_set_buf_noautocmd
		utils.win_set_buf_noautocmd = function(win, buf)
			if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			return win_set_buf_noautocmd(win, buf)
		end
		utils._mark_valid_buffer_guard = true
	end
end

return M
