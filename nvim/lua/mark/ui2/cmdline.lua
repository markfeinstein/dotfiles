local M = {}

function M.setup(context)
	local api = context.api
	local augroup = context.augroup
	local get_valid_ui2_buf = context.get_valid_ui2_buf
	local get_valid_ui2_win = context.get_valid_ui2_win
	local log = context.log
	local search_count = context.search_count
	local ui2 = context.ui2

	-- Pending confirm text: stored when a confirm-kind message arrives,
	-- applied as dialog title when the dialog window opens.
	-- Module-scoped so FileType autocmd can also access it.
	local pending_confirm_text = nil
	local _saved_guicursor = nil
	local _confirm_ns = api.nvim_create_namespace("confirm_dialog")

	--- Highlight key letters in a confirm button string within a buffer line.
	--- Finds [X] and (X) patterns, dims the line, then highlights the key chars.
	--- @param buf integer buffer handle
	--- @param line integer 0-indexed line number
	--- @param text string the button text (as written in the buffer)
	--- @param ns integer namespace for extmarks
	local function highlight_confirm_keys(buf, line, text, ns)
		-- Dim the entire line
		pcall(api.nvim_buf_set_extmark, buf, ns, line, 0, {
			end_row = line + 1,
			end_col = 0,
			hl_group = "Comment",
			priority = 4096,
		})
		-- Highlight key characters: [X] or (X)
		local i = 1
		while i <= #text do
			local c = text:sub(i, i)
			if (c == "[" or c == "(") and i + 2 <= #text then
				local close = c == "[" and "]" or ")"
				if text:sub(i + 2, i + 2) == close then
					-- Key char is at Lua position i+1, 0-indexed column = i
					pcall(api.nvim_buf_set_extmark, buf, ns, line, i, {
						end_row = line,
						end_col = i + 1,
						hl_group = "DiagnosticSignWarn",
						priority = 4096,
					})
					i = i + 3
				else
					i = i + 1
				end
			else
				i = i + 1
			end
		end
	end

	--- Apply two-line confirm dialog layout: question on line 1, buttons on line 2.
	--- Auto-sizes and centers the window. Requires nvim__redraw flush afterward.
	--- @param win integer window handle
	--- @param buf integer buffer handle
	--- @param question string the confirm question text
	--- @param buttons string the button prompt (e.g. "[Y]es, (N)o, (C)ancel: ")
	local function apply_confirm_layout(win, buf, question, buttons)
		local buttons_trimmed = buttons:gsub("%s+$", "")
		local q_width = vim.fn.strdisplaywidth(question)
		local b_width = vim.fn.strdisplaywidth(buttons_trimmed)
		local content_width = math.max(q_width, b_width) + 6
		local cols = vim.o.columns
		local width = math.max(1, math.min(math.max(content_width, 30), cols - 4))

		-- Center each line within the window
		local q_pad = math.max(0, math.floor((width - q_width) / 2))
		local b_pad = math.max(0, math.floor((width - b_width) / 2))
		local q_line = string.rep(" ", q_pad) .. question
		local b_line = string.rep(" ", b_pad) .. buttons_trimmed

		-- Set buffer content: question + buttons
		pcall(api.nvim_buf_set_lines, buf, 0, -1, false, { q_line, b_line })

		-- Apply highlights
		local ns = _confirm_ns
		pcall(api.nvim_buf_clear_namespace, buf, ns, 0, -1)
		pcall(api.nvim_buf_set_extmark, buf, ns, 0, 0, {
			end_row = 1,
			end_col = 0,
			hl_group = "DiagnosticSignWarn",
			priority = 4096,
		})
		highlight_confirm_keys(buf, 1, b_line, ns)

		-- Resize and reposition window
		local row = math.floor(vim.o.lines / 4)
		local col = math.floor((cols - width) / 2)
		pcall(api.nvim_win_set_config, win, {
			relative = "editor",
			width = width,
			height = 2,
			row = row,
			col = col,
			border = "rounded",
			title = { { "  Confirm ", "DiagnosticSignWarn" } },
			title_pos = "center",
			footer = "",
			zindex = 200,
			hide = false,
		})

		pcall(
			api.nvim_set_option_value,
			"winhighlight",
			"Normal:CmdPopup,FloatBorder:DiagnosticSignWarn,FloatTitle:DiagnosticSignWarn,Search:,IncSearch:,CurSearch:,Cursor:CmdPopup,lCursor:CmdPopup,CursorLine:CmdPopup",
			{ win = win }
		)

		-- Hide the cursor via DECTCEM escape sequence.
		-- guicursor + highlight approach doesn't work reliably in terminals;
		-- the terminal emulator draws the cursor independently. DECTCEM (\e[?25l)
		-- is universally supported and tells the terminal to hide the cursor.
		-- Restored in CmdlineLeave when the confirm dialog closes.
		if not _saved_guicursor then
			_saved_guicursor = true
			pcall(api.nvim_ui_send, "\27[?25l")
		end
	end

	local function message_content_text(content)
		local parts = {}
		for _, chunk in ipairs(content or {}) do
			if chunk[2] and chunk[2] ~= "" then
				parts[#parts + 1] = chunk[2]
			end
		end
		return table.concat(parts)
	end

	do
		-- Preserve the custom confirm dialog, but let Snacks.notifier present all
		-- native progress events. UI2 still owns non-progress messages and history.
		local msg_module = ui2.msg
		if type(msg_module) == "table" and type(msg_module.show_msg) == "function" then
			msg_module._mark_orig_show_msg = msg_module._mark_orig_show_msg or msg_module.show_msg
			local original_show_msg = msg_module._mark_orig_show_msg

			msg_module.show_msg = function(tgt, kind, content, replace_last, append, id)
				if kind == "confirm" or kind == "confirm_sub" then
					local text = vim.trim(message_content_text(content))
					if text ~= "" then
						pending_confirm_text = text
					end
					return
				end
				if kind == "progress" then
					return
				end

				local ok, err = pcall(original_show_msg, tgt, kind, content, replace_last, append, id)
				if not ok then
					log.error("native UI2 show_msg failed", err)
				end
			end
		end
	end

	-- Confirm dialog styling
	-- Confirm dialogs (e.g., ":q" with unsaved changes) arrive as two events:
	--   1. cmdline_show(prompt="[Y]es, (N)o, (C)ancel:") → synchronous, renders input
	--   2. msg_show(kind="confirm") → fast event, deferred via vim.schedule
	-- Because msg_show is always deferred, the question text is unavailable when
	-- cmdline_show runs. The cmdline_show wrapper schedules a deferred callback
	-- that runs AFTER msg_show (FIFO ordering), reads pending_confirm_text, and
	-- upgrades the cmdline body with the question/buttons and nvim__redraw flush.

	-- Cmdline window styling

	-- Track buffer ID instead of boolean so re-patch works after buffer recreation
	local cmdline_patched_buf = -1
	local cmdline_generation = 0
	local cmdline_state = {
		source_buf = nil,
		prefix_offset = 0,
		prev_cols = 0,
		prev_lines = 0,
		cached_width = nil,
		cached_row = nil,
		cached_col = nil,
		cmd_win_saved = nil,
		last_title = nil,
		last_border_hl = nil,
		last_height = nil,
		last_wh = nil,
		has_extmarks = false,
		confirm_active = false,
		confirm_question = nil,
		confirm_buttons = nil,
		input_prompt_active = false,
		input_text = "",
	}
	local cmdline_search_counter = search_count.new_counter()

	local function clear_confirm_state()
		pending_confirm_text = nil
		cmdline_state.confirm_active = false
		cmdline_state.confirm_question = nil
		cmdline_state.confirm_buttons = nil
	end

	local function restore_confirm_cursor()
		if _saved_guicursor then
			_saved_guicursor = nil
			pcall(api.nvim_ui_send, "\27[?25h")
		end
	end

	local function patch_cmdline()
		local cmd_buf = get_valid_ui2_buf(ui2.bufs and ui2.bufs.cmd)
		if not cmd_buf then
			return -- Buffer not ready or invalid, skip silently
		end
		if cmdline_patched_buf == cmd_buf then
			return
		end
		cmdline_patched_buf = cmd_buf

		local cmdmod = ui2.cmd
		if
			type(cmdmod) ~= "table"
			or type(cmdmod.cmdline_show) ~= "function"
			or type(cmdmod.cmdline_pos) ~= "function"
		then
			log.warn("UI2 cmdline internals are unavailable; skipping custom cmdline wrapper")
			return
		end

		local ns = api.nvim_create_namespace("cmdline_icons")

		-- Pre-computed winhighlight suffix (static parts)
		local WH_SUFFIX = ",Search:,IncSearch:,CurSearch:"

		-- Store canonical original functions on the shared UI2 cmd module so
		-- repeated :source/dofile rebuilds exactly one wrapper layer instead of
		-- treating a previous wrapper closure as the new original.
		cmdmod._mark_orig_cmdline_show = cmdmod._mark_orig_cmdline_show or cmdmod.cmdline_show
		cmdmod._mark_orig_cmdline_pos = cmdmod._mark_orig_cmdline_pos or cmdmod.cmdline_pos

		local orig_show = cmdmod._mark_orig_cmdline_show
		local orig_pos = cmdmod._mark_orig_cmdline_pos

		-- Wrap cmdline_pos to correct cursor positioning when buffer text differs
		-- from UI2's stored prompt/cmdline representation.
		cmdmod.cmdline_pos = function(pos)
			local win = ui2.wins and ui2.wins.cmd
			if cmdline_state.input_prompt_active then
				if not win or not api.nvim_win_is_valid(win) then
					return
				end
				local input_before_cursor = cmdline_state.input_text:sub(1, pos)
				local translated_pos = #vim.fn.strtrans(input_before_cursor)
				pcall(api.nvim_win_set_cursor, win, { 1, translated_pos })
				return
			end
			if cmdline_state.prefix_offset > 0 then
				-- Buffer content was modified by strip_cmd_prefix, so upstream's
				-- cmdbuff/promptlen are stale. Compute adjusted cursor position directly.
				if not win or not api.nvim_win_is_valid(win) then
					return
				end
				local adjusted = math.max(0, pos - cmdline_state.prefix_offset)
				local row = api.nvim_win_get_cursor(win)[1] -- 1-indexed for display
				pcall(api.nvim_win_set_cursor, win, { row, 1 + adjusted })
				return
			end
			orig_pos(pos)
		end

		-- calc_position returns a 'changed' boolean to avoid dead-code comparison
		local function calc_position()
			local cols, lines = vim.o.columns, vim.o.lines
			if cols ~= cmdline_state.prev_cols or lines ~= cmdline_state.prev_lines then
				cmdline_state.prev_cols = cols
				cmdline_state.prev_lines = lines
				cmdline_state.cached_width = math.min(math.max(60, math.min(100, math.floor(cols * 0.4))), cols - 4)
				cmdline_state.cached_row = math.floor(lines / 4)
				cmdline_state.cached_col = math.floor((cols - cmdline_state.cached_width) / 2)
				return cmdline_state.cached_width, cmdline_state.cached_row, cmdline_state.cached_col, true
			end
			return cmdline_state.cached_width, cmdline_state.cached_row, cmdline_state.cached_col, false
		end

		local function save_cmd_win_config(win)
			if cmdline_state.cmd_win_saved then
				return
			end
			local cfg = api.nvim_win_get_config(win)
			cmdline_state.cmd_win_saved = {
				relative = cfg.relative,
				anchor = cfg.anchor,
				col = cfg.col,
				row = cfg.row,
				width = cfg.width,
				border = cfg.border,
			}
		end

		-- Helper to strip command prefixes from buffer (help, lua, etc.)
		local function strip_cmd_prefix(buf, patterns)
			local ok, lines = pcall(api.nvim_buf_get_lines, buf, 0, 1, false)
			if not ok or not lines[1] then
				return
			end
			for _, pat in ipairs(patterns) do
				local captured = lines[1]:match(pat)
				if captured then
					captured = captured:gsub("%s+$", "")
					pcall(api.nvim_buf_set_lines, buf, 0, 1, false, { " " .. captured .. " " })
					return
				end
			end
		end

		-- Wrapper for cmdline_show to apply custom styling
		cmdmod.cmdline_show = function(content, pos, firstc, prompt, indent, level, hl_id)
			-- Suppress cmdheight during orig_show to prevent statusline shift.
			-- Neovim 0.13 made 'cmdheight' tab-local, and vim._with({ o = { cmdheight = 0 } })
			-- currently crashes in vim/_core/shared.lua because tab-local options are not
			-- handled there yet. Save/restore manually instead.
			local prev_cmdheight = vim.opt.cmdheight:get()
			if prev_cmdheight ~= 0 then
				vim.opt.cmdheight = 0
			end
			local ok, err = pcall(orig_show, content, pos, firstc, prompt, indent, level, hl_id)
			if vim.opt.cmdheight:get() ~= prev_cmdheight then
				vim.opt.cmdheight = prev_cmdheight
			end
			if not ok then
				error(err, 0)
			end
			local win = get_valid_ui2_win(ui2.wins and ui2.wins.cmd)
			local buf = get_valid_ui2_buf(ui2.bufs and ui2.bufs.cmd)
			if not win or not buf then
				-- Window/buffer invalid after orig_show - attempt recovery once
				log.warn("UI2 cmdline target invalid after cmdline_show; attempting recovery")
				if type(ui2.check_targets) == "function" then
					ui2.check_targets()
				end
				win = get_valid_ui2_win(ui2.wins and ui2.wins.cmd)
				buf = get_valid_ui2_buf(ui2.bufs and ui2.bufs.cmd)
				if not win or not buf then
					log.error("UI2 cmdline target still invalid after recovery")
					return -- Still invalid after recovery, skip silently
				end
			end

			-- orig_show temporarily raises 'cmdheight'; restoring it to 0 causes
			-- UI2's OptionSet handler to hide the native cmd window. Unhide it on
			-- every redraw, not only when our title/border config changes.
			local cfg_ok, cfg = pcall(api.nvim_win_get_config, win)
			if cfg_ok and cfg.hide then
				pcall(api.nvim_win_set_config, win, { hide = false })
			end

			-- Reset body/cursor adjustments for new cmdline content.
			cmdline_state.prefix_offset = 0
			cmdline_state.input_prompt_active = false
			cmdline_state.input_text = ""

			-- Reset confirm state when entering a non-confirm cmdline
			if firstc ~= "" or prompt == "" then
				cmdline_state.confirm_active = false
				cmdline_state.confirm_question = nil
				cmdline_state.confirm_buttons = nil
			end

			-- Fast-path single-chunk content (avoids table alloc + concat)
			local text
			if #content == 1 then
				text = content[1][2]
			else
				local parts = {}
				for i, chunk in ipairs(content) do
					parts[i] = chunk[2]
				end
				text = table.concat(parts)
			end

			-- Determine styling based on firstc and content
			local border_hl, title, icon, icon_hl
			local display_text = text
			local input_prompt = false
			local substitute_count_pattern = firstc == ":" and search_count.substitute_pattern(text) or nil

			if firstc == "/" then
				-- Forward search
				border_hl = "DiagnosticSignWarn"
				title, icon, icon_hl = " Search " .. icons.down .. " ", " ", "DiagnosticSignWarn"
			elseif firstc == "?" then
				-- Backward search
				border_hl = "DiagnosticSignWarn"
				title, icon, icon_hl = " Search " .. icons.up .. " ", " ", "DiagnosticSignWarn"
			elseif firstc == "=" then
				-- Expression register
				border_hl = "DiagnosticSignInfo"
				title, icon, icon_hl = " Expression ", "", "DiagnosticSignInfo"
			elseif firstc == "" and prompt ~= "" then
				-- Input prompt (from vim.fn.input()) or confirm dialog
				local confirm_q = pending_confirm_text
					or (cmdline_state.confirm_active and cmdline_state.confirm_question)
				if confirm_q then
					-- Confirm dialog: apply two-line body layout and return early.
					-- apply_confirm_layout handles window config, buffer content,
					-- and highlights — skip the normal cmdline styling entirely.
					apply_confirm_layout(win, buf, confirm_q, cmdline_state.confirm_buttons or prompt)
					cmdline_state.confirm_active = true
					cmdline_state.confirm_question = confirm_q
					cmdline_state.confirm_buttons = cmdline_state.confirm_buttons or prompt
					pending_confirm_text = nil
					return
				else
					input_prompt = true
					border_hl = "DiagnosticSignInfo"
					title, icon, icon_hl = " " .. vim.trim(prompt) .. " ", icons.keyboard, "DiagnosticSignInfo"

					-- UI2 stores the prompt and editable value together. Replacing the
					-- whole line keeps only the translated value and invalidates UI2's
					-- shaded prompt extmark. Track the value so later cmdline_pos events
					-- do not apply UI2's now-stale prompt offset.
					cmdline_state.input_prompt_active = true
					cmdline_state.input_text = text
					local translated_text = vim.fn.strtrans(text)
					pcall(api.nvim_buf_set_lines, buf, 0, -1, false, { translated_text .. " " })
					local translated_pos = #vim.fn.strtrans(text:sub(1, pos))
					pcall(api.nvim_win_set_cursor, win, { 1, translated_pos })
					-- Deferred confirm upgrade: msg_show is a fast event (always
					-- deferred via vim.schedule). A vim.schedule from here runs
					-- AFTER the queued msg_show handler (FIFO ordering), so
					-- pending_confirm_text will be available if this is a confirm.
					local deferred_win = win
					local deferred_buf = buf
					local captured_prompt = prompt
					local captured_generation = cmdline_generation
					vim.schedule(function()
						if captured_generation ~= cmdline_generation then
							return
						end
						if not pending_confirm_text then
							return
						end
						if not api.nvim_win_is_valid(deferred_win) or not api.nvim_buf_is_valid(deferred_buf) then
							return
						end
						local question = pending_confirm_text
						pending_confirm_text = nil
						cmdline_state.confirm_active = true
						cmdline_state.confirm_question = question
						cmdline_state.confirm_buttons = captured_prompt
						apply_confirm_layout(deferred_win, deferred_buf, question, captured_prompt)
						pcall(api.nvim__redraw, { flush = true, win = deferred_win })
					end)
				end
			elseif firstc == ":" then
				-- Ex commands - sub-detect specific types
				if text:match("^!") then
					-- Shell command - also strip the ! from the buffer
					border_hl = "DiagnosticSignError"
					title, icon, icon_hl = " Shell ", " ", "DiagnosticSignError"

					-- Remove the ! character (position 1 in buffer after we replaced : with space)
					local rd_ok, lines = pcall(api.nvim_buf_get_lines, buf, 0, 1, false)
					if rd_ok and lines[1] and lines[1]:sub(2, 2) == "!" then
						lines[1] = lines[1]:sub(1, 1) .. lines[1]:sub(3)
						pcall(api.nvim_buf_set_lines, buf, 0, 1, false, lines)
						cmdline_state.prefix_offset = 1 -- Track the removed "!" byte for cursor correction
					end
				elseif text:match("^lua%s") or text:match("^=%s") then
					-- Lua command
					border_hl = "DiagnosticSignHint"
					title, icon, icon_hl = " Lua ", "", "DiagnosticSignHint"
				elseif text:match("^help%s") or text:match("^h%s") then
					-- Help command (help or h followed by space)
					border_hl = "DiagnosticSignOk"
					title, icon, icon_hl = " Help ", " ", "DiagnosticSignOk"
				elseif substitute_count_pattern ~= nil then
					-- Substitute
					border_hl = "DiagnosticSignWarn"
					title, icon, icon_hl = " Substitute ", "", "DiagnosticSignWarn"
				else
					-- Default Ex command
					border_hl = "DiagnosticSignInfo"
					title, icon, icon_hl = " Command ", " ", "DiagnosticSignInfo"
				end
			else
				-- Fallback
				border_hl = "DiagnosticSignInfo"
				title, icon, icon_hl = " Command ", ">", "DiagnosticSignInfo"
			end

			-- Nested cmdline indicator (e.g., <C-r>= inside : mode)
			if level > 1 then
				title = title:sub(1, -2) .. " ↩ nested "
			end

			-- Calculate centered position; changed flag tells us if position moved
			local width, row, col, position_changed = calc_position()

			-- Dynamic height: input prompts use the actual wrapped window text on
			-- every redraw. Other cmdline kinds retain their existing calculation.
			local height
			if input_prompt then
				if api.nvim_win_get_width(win) ~= width then
					-- Text height uses the current window width. Preserve UI2's original
					-- geometry before resizing so CmdlineLeave can still restore it.
					save_cmd_win_config(win)
					pcall(api.nvim_win_set_width, win, width)
				end
				height = math.min(5, math.max(1, api.nvim_win_text_height(win).all))
			else
				local content_len = #display_text + 1 -- +1 for icon/space prefix
				height = math.max(1, math.ceil(content_len / width))
			end

			-- Tell blink.cmp where the cmdline content starts (1-indexed row, 0-indexed col).
			-- Input bodies have no icon/prompt prefix, and wrapped input menus belong
			-- below the complete box. Other cmdline kinds retain their existing offsets.
			-- Guard: only write vim.g when changed (avoids variable-watch callbacks on every keystroke)
			local new_r = input_prompt and (row + height + 2) or (row + 3)
			local new_c = input_prompt and (col + 1) or (col + 3)
			local cur_pos = vim.g.ui_cmdline_pos
			if not cur_pos or cur_pos[1] ~= new_r or cur_pos[2] ~= new_c then
				vim.g.ui_cmdline_pos = { new_r, new_c }
			end

			-- Apply window configuration (skip if title/border/position all unchanged)
			local config_changed = position_changed
				or title ~= cmdline_state.last_title
				or border_hl ~= cmdline_state.last_border_hl
			if config_changed then
				save_cmd_win_config(win)
				local win_cfg = {
					relative = "editor",
					border = "rounded",
					width = width,
					height = height,
					row = row,
					col = col,
					zindex = 200,
					title = title,
					title_pos = "center",
					hide = false,
				}
				pcall(api.nvim_win_set_config, win, win_cfg)
				cmdline_state.last_title = title
				cmdline_state.last_border_hl = border_hl
				cmdline_state.last_height = height
			end

			if height ~= cmdline_state.last_height then
				if not config_changed then
					pcall(api.nvim_win_set_config, win, { height = height })
				end
				cmdline_state.last_height = height
			end

			-- Apply window highlights only when changed
			local wh = "Normal:CmdPopup,FloatBorder:" .. border_hl .. ",FloatTitle:" .. border_hl
			wh = wh .. WH_SUFFIX
			if wh ~= cmdline_state.last_wh then
				api.nvim_set_option_value("winhighlight", wh, { win = win })
				cmdline_state.last_wh = wh
			end

			-- Replace firstc with space in buffer (preserves byte length for cursor math)
			-- Skip this for input prompts where firstc is empty
			if #firstc > 0 then
				local rd_ok, lines = pcall(api.nvim_buf_get_lines, buf, 0, 1, false)
				if rd_ok and lines[1] and #lines[1] >= #firstc then
					local spaces = string.rep(" ", #firstc)
					lines[1] = spaces .. lines[1]:sub(#firstc + 1)
					pcall(api.nvim_buf_set_lines, buf, 0, 1, false, lines)
				end
			end

			-- Only clear namespace when extmarks were previously placed
			if cmdline_state.has_extmarks then
				pcall(api.nvim_buf_clear_namespace, buf, ns, 0, -1)
				cmdline_state.has_extmarks = false
			end

			-- Overlay the space(s) with the icon (or skip for input prompts)
			if #firstc > 0 then
				pcall(api.nvim_buf_set_extmark, buf, ns, 0, 0, {
					virt_text = { { icon, icon_hl } },
					virt_text_pos = "overlay",
					hl_mode = "combine",
					end_row = 0,
					end_col = #firstc,
				})
				cmdline_state.has_extmarks = true
			end

			local function request_count(pattern, requested_text, formatter)
				if not pattern or #pattern < 2 then
					return false
				end
				local target_buf = cmdline_state.source_buf or api.nvim_get_current_buf()
				local requested_generation = cmdline_generation
				search_count.request(cmdline_search_counter, "cmdline", {
					bufnr = target_buf,
					searchcount_opts = { pattern = pattern, timeout = 20 },
					validate = function()
						return cmdline_generation == requested_generation
							and get_valid_ui2_buf(buf) ~= nil
							and get_valid_ui2_win(win) ~= nil
							and vim.fn.getcmdline() == requested_text
					end,
					apply = function(sc)
						local count_text, count_hl = formatter(sc)
						if not count_text then
							return
						end
						local mark_ok = pcall(api.nvim_buf_set_extmark, buf, ns, 0, 0, {
							virt_text = { { count_text, count_hl } },
							virt_text_pos = "right_align",
						})
						if mark_ok then
							cmdline_state.has_extmarks = true
							-- The count is added from a timer callback after UI2's own
							-- cmdline redraw has finished. Flush this internal window so
							-- the extmark reaches the terminal without another keypress.
							pcall(api.nvim__redraw, { flush = true, win = win })
						end
					end,
				})
				return true
			end

			local count_requested = false

			-- Debounced so cmdline_show can stay cheap while typing. The search form
			-- searches for the requested text; substitute uses the parsed pattern.
			if firstc == "/" or firstc == "?" then
				count_requested = request_count(text, text, search_count.format_position)
			elseif firstc == ":" then
				count_requested = request_count(substitute_count_pattern, text, search_count.format_matches)
			end

			if not count_requested then
				search_count.cancel(cmdline_search_counter, "cmdline")
			end

			-- Special handling: strip command prefix for help commands
			if firstc == ":" and (text:match("^help%s") or text:match("^h%s")) then
				local prefix = text:match("^(help%s+)") or text:match("^(h%s+)")
				if prefix then
					cmdline_state.prefix_offset = #prefix
				end
				strip_cmd_prefix(buf, { "^%shelp%s+(.*)", "^%sh%s+(.*)" })
			end

			-- Special handling: strip command prefix for Lua commands
			if firstc == ":" and (text:match("^lua%s") or text:match("^=%s")) then
				local prefix = text:match("^(lua%s+)") or text:match("^(=%s+)")
				if prefix then
					cmdline_state.prefix_offset = #prefix
				end
				strip_cmd_prefix(buf, { "^%slua%s+(.*)", "^%s=%s+(.*)" })
			end
		end
	end

	api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = "cmd",
		callback = patch_cmdline,
	})
	patch_cmdline()

	-- Reset cmdline styling state for a fresh session.
	api.nvim_create_autocmd("CmdlineEnter", {
		group = augroup,
		callback = function()
			cmdline_generation = cmdline_generation + 1
			cmdline_state.source_buf = api.nvim_get_current_buf()
			cmdline_state.prefix_offset = 0
			cmdline_state.input_prompt_active = false
			cmdline_state.input_text = ""
			cmdline_state.last_title = nil
			cmdline_state.last_border_hl = nil
			cmdline_state.last_wh = nil
			cmdline_state.last_height = nil
			cmdline_state.has_extmarks = false
			clear_confirm_state()
			restore_confirm_cursor()
		end,
	})

	-- Restore the original cmdline window position for post-command messages.
	api.nvim_create_autocmd("CmdlineLeave", {
		group = augroup,
		callback = function()
			search_count.cancel_all(cmdline_search_counter)
			cmdline_generation = cmdline_generation + 1
			cmdline_state.source_buf = nil
			clear_confirm_state()
			-- Restore cursor if it was hidden during a confirm dialog
			restore_confirm_cursor()

			local win = get_valid_ui2_win(ui2.wins and ui2.wins.cmd)
			if win and cmdline_state.cmd_win_saved then
				pcall(api.nvim_win_set_config, win, cmdline_state.cmd_win_saved)
			end
			cmdline_state.cmd_win_saved = nil
		end,
	})

	-- Safety net: ensure terminal cursor is restored if Neovim exits
	-- while the confirm dialog cursor was hidden (e.g., :q from confirm).
	api.nvim_create_autocmd("VimLeavePre", {
		group = augroup,
		callback = function()
			restore_confirm_cursor()
		end,
	})

	-- Invalidate cached cmdline geometry when the editor layout changes.
	api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
		group = augroup,
		callback = function()
			local win = get_valid_ui2_win(ui2.wins and ui2.wins.cmd)
			-- Invalidate cmdline position cache
			if win then
				cmdline_state.prev_cols = 0
				cmdline_state.prev_lines = 0
			end
		end,
	})
end

return M
