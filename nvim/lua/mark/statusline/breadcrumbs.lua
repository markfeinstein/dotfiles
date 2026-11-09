local doc_symbols = require("mark.statusline_doc_symbols")
local statusline_escape_literal = require("mark.statusline.util").escape_literal

local M = {}

function M.setup(symbols)
	local root_name_cache = {}
	local rel_path_cache = { path_base = nil, fname = nil, result = nil }
	local reset_symbol_chain_cache

	local function breadcrumb_label(name)
		name = tostring(name or "")
		-- Servers can use an entire multiline literal as a symbol name.
		local first_line = name:match("^[^\r\n]*")
		local shortened = #first_line < #name
		local label = first_line:gsub("%c", " ")
		local max_width = 60
		if vim.fn.strdisplaywidth(label .. (shortened and "…" or "")) > max_width then
			shortened = true
			local chars = math.min(vim.fn.strchars(label), max_width)
			label = vim.fn.strcharpart(label, 0, chars)
			while vim.fn.strdisplaywidth(label .. "…") > max_width do
				chars = chars - 1
				label = vim.fn.strcharpart(label, 0, chars)
			end
		end
		return statusline_escape_literal(label .. (shortened and "…" or ""))
	end

	local function get_symbol_kind_name(kind_num)
		local lsp = package.loaded["vim.lsp"]
		local symbol_kind = lsp and lsp.protocol and lsp.protocol.SymbolKind
		if not symbol_kind then
			return nil
		end
		return symbol_kind[kind_num]
	end

	local function get_mini_icon(kind)
		local icons = package.loaded["mini.icons"]
		if not icons or kind == nil then
			return nil, nil
		end

		-- Resolve numeric kind to string name in O(1)
		local resolved = kind
		if type(kind) == "number" then
			resolved = get_symbol_kind_name(kind)
			if not resolved then
				return nil, nil
			end
		end

		local ok, icon, hl = pcall(icons.get, "lsp", resolved)
		if ok and icon and icon ~= "" then
			return (type(icon) == "table") and (icon[1] or "") or tostring(icon), (type(hl) == "string") and hl or nil
		end
		return nil, nil
	end

	-- Try to split Go method names like "(*T).Method" or "T.Method" into {"T","Method"}
	local function split_go_method_name(name)
		if not name or type(name) ~= "string" then
			return nil
		end
		-- Pattern: (Type).Method or (*Type).Method
		local typ, method = name:match("^%((%*?[%w_]+)%)%.(.+)$")
		if typ and method then
			typ = typ:gsub("^%*", "")
			return typ, method
		end
		-- Pattern: Type.Method
		typ, method = name:match("^([%w_]+)%.(.+)$")
		if typ and method then
			return typ, method
		end
		return nil
	end

	-- Lightweight Tree-sitter scope suffix (shallow, cheap). Returns a short label
	-- like "literal", "call", "if", etc. Only used as a small suffix for Go.
	local _go_ts_scope_labels = {
		composite_literal = "literal",
		keyed_element = "field",
		call_expression = "call",
		if_statement = "if",
		for_statement = "for",
		switch_statement = "switch",
		select_statement = "select",
		return_statement = "return",
		function_literal = "func literal",
		literal_element = "literal",
	}
	local _ts_scope_cache = { bufnr = -1, line = -1, col = -1, changedtick = -1, result = nil }

	local function get_treesitter_scope_suffix(bufnr)
		if not (package.loaded["vim.treesitter"] or pcall(require, "vim.treesitter")) then
			return nil
		end
		local cursor = vim.api.nvim_win_get_cursor(0)
		local line = cursor[1]
		local col = cursor[2]
		local changedtick = vim.b[bufnr].changedtick
		if
			_ts_scope_cache.bufnr == bufnr
			and _ts_scope_cache.line == line
			and _ts_scope_cache.col == col
			and _ts_scope_cache.changedtick == changedtick
		then
			return _ts_scope_cache.result
		end
		local ok, node = pcall(vim.treesitter.get_node)
		if not ok or not node then
			_ts_scope_cache = { bufnr = bufnr, line = line, col = col, changedtick = changedtick, result = nil }
			return nil
		end

		-- Walk up parent chain and find the first mapping
		local search = node
		while search do
			local label = _go_ts_scope_labels[search:type()]
			if label then
				_ts_scope_cache = { bufnr = bufnr, line = line, col = col, changedtick = changedtick, result = label }
				return label
			end
			search = search:parent()
		end

		_ts_scope_cache = { bufnr = bufnr, line = line, col = col, changedtick = changedtick, result = nil }
		return nil
	end

	-- Defer breadcrumb cache autocmds to avoid startup cost
	vim.schedule(function()
		local breadcrumb_group = vim.api.nvim_create_augroup("statusline_breadcrumb_cache")

		-- Fetch document symbols when relevant events happen (async). Do NOT
		-- run blocking LSP requests in the statusline render path; instead we
		-- prefetch and cache the symbol tree and trigger a redraw when ready.
		local function schedule_fetch(bufnr, delay)
			doc_symbols.schedule(bufnr, delay, {
				on_update = function(updated_buf)
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(updated_buf) then
							pcall(vim.cmd.redrawstatus)
						end
					end)
				end,
			})
		end

		-- Trigger fetch on events that can change document symbols. The scheduler
		-- coalesces unchanged name/changedtick/client sets, including repeated
		-- BufReadPost/BufEnter/LspAttach/CursorHold events.
		vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufEnter", "LspAttach" }, {
			group = breadcrumb_group,
			callback = function(ev)
				schedule_fetch(ev.buf, 0)
			end,
			desc = "Fetch/refresh document symbols for statusline breadcrumbs",
		})

		vim.api.nvim_create_autocmd("LspDetach", {
			group = breadcrumb_group,
			callback = function(ev)
				root_name_cache[ev.buf] = nil
				reset_symbol_chain_cache(ev.buf)
				doc_symbols.prune(ev.buf)
				schedule_fetch(ev.buf, 0)
			end,
			desc = "Prune detached document-symbol clients for statusline breadcrumbs",
		})

		-- Debounced fetch while editing to avoid spamming slow LSP servers.
		-- Keep this fairly relaxed; breadcrumbs do not need to update on every edit.
		vim.api.nvim_create_autocmd({ "TextChanged", "CursorHold" }, {
			group = breadcrumb_group,
			callback = function(ev)
				schedule_fetch(ev.buf, 1000)
			end,
			desc = "Debounced fetch for document symbols while editing",
		})

		-- Clean up caches for deleted/unloaded buffers.
		vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "BufUnload" }, {
			group = breadcrumb_group,
			callback = function(ev)
				doc_symbols.cleanup(ev.buf)
				root_name_cache[ev.buf] = nil
				reset_symbol_chain_cache(ev.buf)
			end,
			desc = "Clean up document symbols and root caches",
		})

		-- Invalidate root and document-symbol keys on file rename
		vim.api.nvim_create_autocmd("BufFilePost", {
			group = breadcrumb_group,
			callback = function(ev)
				root_name_cache[ev.buf] = nil
				rel_path_cache = { path_base = nil, fname = nil, result = nil }
				reset_symbol_chain_cache(ev.buf)
				doc_symbols.invalidate(ev.buf)
				schedule_fetch(ev.buf, 0)
			end,
			desc = "Invalidate statusline caches on file rename",
		})

		-- Cache management: invalidate root cache when root inputs can change.
		local cache_group = vim.api.nvim_create_augroup("statusline_cache")
		vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach", "DirChanged" }, {
			group = cache_group,
			callback = function(ev)
				if ev.event == "DirChanged" then
					root_name_cache = {}
					rel_path_cache = { path_base = nil, fname = nil, result = nil }
					reset_symbol_chain_cache()
				else
					local buf = ev.buf or vim.api.nvim_get_current_buf()
					root_name_cache[buf] = nil
					reset_symbol_chain_cache(buf)
				end
			end,
			desc = "Clear statusline root cache",
		})
	end)

	--- Helper to check if cursor is within an LSP range.
	--- Converts through vim.range.lsp() so UTF-16/UTF-8 LSP character offsets are
	--- compared against the cursor's byte-indexed column correctly.
	--- @param bufnr number Buffer number
	--- @param line number 0-indexed line number
	--- @param col number 0-indexed byte column number
	--- @param lsp_range table LSP range object
	--- @param position_encoding string LSP position encoding for the source client
	--- @return boolean
	local function cursor_in_lsp_range(bufnr, line, col, lsp_range, position_encoding)
		local ok, range = pcall(vim.range.lsp, bufnr, lsp_range, position_encoding or "utf-16")
		if not ok or not range then
			return false
		end

		local pos = vim.pos(bufnr, line, col)
		-- vim.range.has() handles the ordering; explicitly preserve LSP's
		-- end-exclusive semantics because a Pos at range.end is otherwise included.
		return range:has(pos) and not (line == range.end_row and col == range.end_col)
	end

	-- Hoisted to module scope to avoid closure allocation on every render
	local function _format_symbol_segment(name, kind)
		local icon_text, icon_hl = get_mini_icon(kind)
		if icon_text and icon_text ~= "" then
			return string.format(
				"%%#%s#%s %%#StatusLineBreadcrumbSymbol#%s",
				icon_hl or "StatusLineBreadcrumbSymbol",
				icon_text,
				breadcrumb_label(name)
			)
		end
		return breadcrumb_label(name)
	end

	local function _find_containing_symbols(bufnr, syms, line, col, ft, position_encoding, depth)
		depth = depth or 0
		if depth > 10 then
			return {}
		end

		local chain = {}
		for _, sym in ipairs(syms) do
			local range = sym.location and sym.location.range or sym.range
			if range and cursor_in_lsp_range(bufnr, line, col, range, position_encoding) then
				local name = sym.name or ""
				if ft == "go" then
					local typ, method = split_go_method_name(name)
					if typ and method then
						table.insert(chain, string.format("%%#StatusLineBreadcrumbSymbol#%s", breadcrumb_label(typ)))
						table.insert(chain, _format_symbol_segment(method, sym.kind))
					else
						table.insert(chain, _format_symbol_segment(name, sym.kind))
					end
				else
					table.insert(chain, _format_symbol_segment(name, sym.kind))
				end

				if sym.children and #sym.children > 0 then
					vim.list_extend(
						chain,
						_find_containing_symbols(bufnr, sym.children, line, col, ft, position_encoding, depth + 1)
					)
				end
				break
			end
		end
		return chain
	end

	--- Get symbol chain from LSP document symbols (async)
	--- @param bufnr number Buffer number
	--- @return string|nil Symbol chain like "Class > Method > Function"
	-- Cache symbol chain by {bufnr, line, col} to avoid re-traversing on every render.
	-- Invalidated by document-symbol cache version and cursor position.
	local _symbol_chain_cache = { bufnr = -1, line = -1, col = -1, changedtick = -1, version = -1, result = nil }

	function reset_symbol_chain_cache(bufnr)
		if not bufnr or _symbol_chain_cache.bufnr == bufnr then
			_symbol_chain_cache = { bufnr = -1, line = -1, col = -1, changedtick = -1, version = -1, result = nil }
		end
	end

	local function cache_symbol_chain_result(bufnr, line, col, changedtick, version, result)
		_symbol_chain_cache = {
			bufnr = bufnr,
			line = line,
			col = col,
			changedtick = changedtick,
			version = version,
			result = result,
		}
		return result
	end

	local function get_symbol_chain(bufnr)
		-- Get cursor position (0-indexed for LSP)
		local cursor = vim.api.nvim_win_get_cursor(0)
		local line = cursor[1] - 1
		local col = cursor[2]
		local changedtick = vim.b[bufnr].changedtick
		local version = doc_symbols.version()

		-- Check per-cursor-position cache before any LSP client query.
		if
			_symbol_chain_cache.bufnr == bufnr
			and _symbol_chain_cache.line == line
			and _symbol_chain_cache.col == col
			and _symbol_chain_cache.changedtick == changedtick
			and _symbol_chain_cache.version == version
		then
			return _symbol_chain_cache.result
		end

		-- Only try if LSP is already loaded and attached; do not autoload vim.lsp
		-- from the statusline render path.
		local lsp = package.loaded["vim.lsp"]
		if not lsp then
			return cache_symbol_chain_result(bufnr, line, col, changedtick, version, nil)
		end

		local symbol_clients = lsp.get_clients({
			bufnr = bufnr,
			method = "textDocument/documentSymbol",
		})
		if #symbol_clients == 0 then
			return cache_symbol_chain_result(bufnr, line, col, changedtick, version, nil)
		end

		-- Check currently attached clients that support document symbols for this
		-- buffer. Cached entries for detached/non-supporting clients must not
		-- participate in deterministic selection.
		local active_symbol_clients = {}
		for _, client in ipairs(symbol_clients) do
			active_symbol_clients[client.id or 0] = true
		end

		-- Filetype (used for Go-specific post-processing)
		local ft = vim.bo[bufnr].filetype
		-- Use prefetched document symbols. Do NOT block the statusline renderer.
		local per_client = doc_symbols.cache_for(bufnr)
		if not per_client or vim.tbl_isempty(per_client) then
			return cache_symbol_chain_result(bufnr, line, col, changedtick, version, nil)
		end

		-- Pick deterministic client symbols: smallest currently attached supporting
		-- client_id with cached data (O(N) min, no alloc).
		local min_id = nil
		for id in pairs(per_client) do
			if active_symbol_clients[id] and (not min_id or id < min_id) then
				min_id = id
			end
		end
		local doc_symbols_entry = min_id and per_client[min_id]
		local client_symbols = doc_symbols_entry and doc_symbols_entry.symbols
		if not client_symbols or #client_symbols == 0 then
			return cache_symbol_chain_result(bufnr, line, col, changedtick, version, nil)
		end
		local position_encoding = doc_symbols_entry.position_encoding or "utf-16"

		local chain = _find_containing_symbols(bufnr, client_symbols, line, col, ft, position_encoding)
		-- For Go buffers, append a small Tree-sitter scope suffix (shallow and cheap)
		if ft == "go" and #chain > 0 then
			local ts_suffix = get_treesitter_scope_suffix(bufnr)
			if ts_suffix and ts_suffix ~= "" then
				table.insert(chain, string.format("%%#StatusLineBreadcrumbSymbol#(%s)", ts_suffix))
			end
		end
		if #chain > 0 then
			local result = table.concat(chain, symbols.breadcrumb_separator)
			return cache_symbol_chain_result(bufnr, line, col, changedtick, version, result)
		end

		return cache_symbol_chain_result(bufnr, line, col, changedtick, version, nil)
	end

	-- Cache management autocmds are registered in the consolidated vim.schedule block below.

	local function project_root(bufnr, fname, cwd)
		-- Prefer the attached LSP's root, then common project markers. Fall back to
		-- the window-local cwd only when the file has no detected project root.
		local cached = root_name_cache[bufnr]
		if cached and cached.fname == fname and cached.cwd == cwd then
			return cached
		end

		local lsp = package.loaded["vim.lsp"]
		local client = lsp and lsp.get_clients({ bufnr = bufnr })[1] or nil
		local lsp_root = client and client.root_dir or ""
		local detected_root = lsp_root ~= "" and lsp_root
			or vim.fs.root(
				fname ~= "" and fname or cwd,
				{ ".git", "go.mod", "go.work", "Cargo.toml", "package.json", "Makefile" }
			)
		local path_base = vim.fs.normalize(detected_root or cwd)
		local root_dir = vim.fs.basename(path_base)
		local value = ""
		if root_dir and root_dir ~= "" then
			value = "%#Boolean#"
				.. symbols.directory
				.. statusline_escape_literal(root_dir)
				.. "%#StatusLine#"
				.. symbols.separator
		end

		local result = { fname = fname, cwd = cwd, lsp_root = lsp_root, path_base = path_base, value = value }
		root_name_cache[bufnr] = result
		return result
	end

	--- Smart breadcrumb with truncation
	--- Shows: path > symbols (truncates path if too long)
	--- @return string Formatted breadcrumb string
	local function breadcrumbs(path_base, fname)
		local bufnr = vim.api.nvim_get_current_buf()

		-- Skip for special buffers
		local buftype = vim.bo[bufnr].buftype
		if buftype ~= "" then
			return ""
		end

		-- Skip for special filetypes
		local ft = vim.bo[bufnr].filetype
		if ft == "help" or ft == "man" or ft == "qf" or ft:sub(1, 7) == "snacks_" then
			return ""
		end

		-- Breadcrumbs are computed per-window from the cached document-symbol tree.
		-- Do not cache the formatted breadcrumb per-buffer because the resolved
		-- symbol chain depends on the current cursor position (window-local).

		if fname == "" then
			return ""
		end

		local rel_path
		if rel_path_cache.path_base == path_base and rel_path_cache.fname == fname then
			rel_path = rel_path_cache.result
		else
			rel_path = statusline_escape_literal(vim.fs.relpath(path_base, fname) or vim.fn.fnamemodify(fname, ":~:."))
			rel_path_cache = { path_base = path_base, fname = fname, result = rel_path }
		end

		-- Try to get symbol chain
		local symbol_chain = get_symbol_chain(bufnr)

		-- Format breadcrumb
		local result
		if symbol_chain then
			result = string.format(
				"%%#StatusLineBreadcrumbPath#%%<%s%%#StatusLineBreadcrumbSeparator#%s%%#StatusLineBreadcrumbSymbol#%s%%*",
				rel_path,
				symbols.breadcrumb_separator,
				symbol_chain
			)
		else
			result = string.format("%%#StatusLineBreadcrumbPath#%%<%s%%*", rel_path)
		end

		return result
	end

	return {
		project_root = project_root,
		render = breadcrumbs,
	}
end

return M
