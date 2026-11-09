local api = vim.api
local search_count = require("mark.search_count")

-- Search count display (in-buffer virtual text)
-- Deferred to next tick to reduce synchronous startup load

vim.schedule(function()
	local augroup = api.nvim_create_augroup("search_features")
	local search_count_ns = api.nvim_create_namespace("search_count_buffer")

	-- Track which buffers have search count extmarks (avoid iterating all buffers)
	local search_count_bufs = {}
	local search_counter = search_count.new_counter()

	local function clear_search_count(bufnr)
		if api.nvim_buf_is_valid(bufnr) then
			pcall(api.nvim_buf_clear_namespace, bufnr, search_count_ns, 0, -1)
		end
		search_count_bufs[bufnr] = nil
	end

	local function clear_search_count_state(bufnr)
		search_count.cancel(search_counter, bufnr)
		clear_search_count(bufnr)
	end

	local function searchpos(pattern, flags)
		return vim.npcall(vim.fn.searchpos, pattern, flags)
	end

	-- Use nvim_get_current_buf() instead of vim.fn.bufnr('%')
	local function update_search_count_display()
		local bufnr = api.nvim_get_current_buf()
		if not api.nvim_buf_is_valid(bufnr) then
			return
		end

		-- Only show if hlsearch is active
		if vim.v.hlsearch ~= 1 then
			clear_search_count_state(bufnr)
			return
		end

		-- Get search pattern
		local pattern = vim.fn.getreg("/")
		if pattern == "" then
			clear_search_count(bufnr)
			return
		end

		local requested_win = api.nvim_get_current_win()
		local requested_buf = bufnr
		search_count.request(search_counter, bufnr, {
			bufnr = bufnr,
			on_skip = clear_search_count,
			validate = function(current_buf)
				return vim.v.hlsearch == 1
					and api.nvim_get_current_buf() == requested_buf
					and api.nvim_win_is_valid(requested_win)
					and api.nvim_win_get_buf(requested_win) == current_buf
					and vim.fn.getreg("/") ~= ""
			end,
			apply = function(sc)
				-- Clear previous extmarks from current buffer before deciding whether
				-- the latest result should render a replacement.
				clear_search_count(bufnr)
				if not sc.total or sc.total == 0 then
					return
				end

				-- Get cursor position (0-indexed for extmark)
				local cursor_line = api.nvim_win_get_cursor(requested_win)[1] - 1 -- 0-indexed for buffer ops
				local count_text = search_count.format_position(sc)
				if not count_text then
					return
				end

				-- Keep the count visible at the window edge when the matched line is
				-- short, but move it after the text instead of covering a long line.
				local mark_ok = pcall(api.nvim_buf_set_extmark, bufnr, search_count_ns, cursor_line, 0, {
					virt_text = { { "  " .. count_text, "DiagnosticSignWarn" } },
					virt_text_pos = "eol_right_align",
					priority = 4096,
				})

				if mark_ok then
					search_count_bufs[bufnr] = true
					-- The debounced request completes outside the cursor event that
					-- initiated it, so explicitly flush the affected window.
					pcall(api.nvim__redraw, { flush = true, win = requested_win })
				end
			end,
		})
	end

	-- Clear search count extmarks only from tracked buffers
	local function clear_search_count_all()
		search_count.cancel_all(search_counter)
		for bufnr, _ in pairs(search_count_bufs) do
			if api.nvim_buf_is_valid(bufnr) then
				pcall(api.nvim_buf_clear_namespace, bufnr, search_count_ns, 0, -1)
			end
		end
		search_count_bufs = {}
	end

	-- Record accepted searches before the cmdline closes, then request the count
	-- on the next event-loop turn. At CmdlineLeavePre, the new search register and
	-- v:hlsearch can still describe the previous search.
	api.nvim_create_autocmd("CmdlineLeavePre", {
		group = augroup,
		-- Pattern uses Vim autocommand syntax: '\\?' matches the literal '?' firstc
		pattern = { "/", "\\?" },
		callback = function()
			-- Only show count if search was executed (<CR>), not aborted (<Esc> or <C-c>)
			if vim.v.char ~= "\r" then
				return
			end
			local requested_buf = api.nvim_get_current_buf()
			vim.schedule(function()
				if api.nvim_buf_is_valid(requested_buf) and api.nvim_get_current_buf() == requested_buf then
					update_search_count_display()
				end
			end)
		end,
	})

	-- ============================================================================
	-- Flash Search Results (0.12+ vim.hl.range)
	-- ============================================================================
	-- Briefly highlight the current match after leaving the / or ? command line.

	api.nvim_create_autocmd("CmdlineLeave", {
		group = augroup,
		pattern = { "/", "\\?" },
		callback = function()
			local leave_buf = api.nvim_get_current_buf()
			local leave_ok, leave_search = pcall(vim.fn.getreg, "/")
			local leave_pos = leave_ok and leave_search ~= "" and searchpos(leave_search, "cn") or nil
			if not leave_pos or leave_pos[1] == 0 then
				clear_search_count(leave_buf)
			end
			vim.schedule(function()
				local bufnr = api.nvim_get_current_buf()
				-- Get current search pattern
				local ok, search = pcall(vim.fn.getreg, "/")
				if not ok or search == "" then
					clear_search_count_state(bufnr)
					return
				end

				-- Get current match position
				local pos = searchpos(search, "cn")
				if not pos or pos[1] == 0 then
					clear_search_count_state(bufnr)
					return
				end

				-- Get match end position
				local match_end = searchpos(search, "cne")
				if not match_end or match_end[1] == 0 then
					clear_search_count_state(bufnr)
					return
				end

				-- Flash the current match with IncSearch highlight
				-- timeout: 150ms flash duration
				-- priority: 200 to appear above other highlights
				pcall(
					vim.hl.range,
					0,
					-1,
					"IncSearch",
					{ pos[1] - 1, pos[2] - 1 },
					{ match_end[1] - 1, match_end[2] },
					{
						timeout = 150,
						priority = 200,
					}
				)
			end)
		end,
		desc = "Flash search result after / or ? cmdline (0.12+ vim.hl.range)",
	})

	-- Clear blink.cmp cmdline position when cmdline closes
	api.nvim_create_autocmd("CmdlineLeavePre", {
		group = augroup,
		callback = function()
			vim.g.ui_cmdline_pos = nil
		end,
	})

	-- Replace keymap wrapping with CursorMoved autocmd
	-- This is less intrusive: no key interception, works with all plugins,
	-- respects user mappings for n/N/*/# without bang=true issues.
	api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		callback = function()
			if vim.v.hlsearch ~= 1 then
				-- If hlsearch just turned off, clean up any stale extmarks
				clear_search_count_state(api.nvim_get_current_buf())
				return
			end
			update_search_count_display()
		end,
	})

	api.nvim_create_autocmd({ "BufLeave", "BufDelete" }, {
		group = augroup,
		callback = function(ev)
			clear_search_count_state(ev.buf)
		end,
	})

	api.nvim_create_autocmd("BufWipeout", {
		group = augroup,
		callback = function(ev)
			search_count.forget(search_counter, ev.buf)
			clear_search_count(ev.buf)
		end,
	})

	-- Create command and mapping to clear search highlights and virtual text
	api.nvim_create_user_command("NohlClear", function()
		vim.cmd("nohlsearch")
		clear_search_count_all()
	end)

	local function stop_active_snippet()
		if vim.snippet.active() then
			vim.snippet.stop()
		end
	end

	-- Map <Esc> to clear search highlighting and any active native snippet state.
	vim.keymap.set("n", "<Esc>", function()
		stop_active_snippet()
		if vim.v.hlsearch == 1 then
			return "<Cmd>NohlClear<CR>"
		end
		return "<Esc>"
	end, { silent = true, expr = true })

	vim.keymap.set({ "i", "s" }, "<Esc>", function()
		stop_active_snippet()
		return "<Esc>"
	end, { silent = true, expr = true })

	-- Replace cnoreabbrev with CmdlineLeavePre autocmd so executed :nohlsearch
	-- commands clear virtual text after the command line closes.
	api.nvim_create_autocmd("CmdlineLeavePre", {
		group = augroup,
		pattern = ":",
		callback = function()
			-- Only act on executed commands (not aborted)
			if vim.v.char ~= "\r" then
				return
			end
			-- Schedule so we run after the command has executed
			vim.schedule(function()
				-- Check if hlsearch was just turned off (nohlsearch was run)
				if vim.v.hlsearch == 0 then
					clear_search_count_all()
				end
			end)
		end,
	})
end)
