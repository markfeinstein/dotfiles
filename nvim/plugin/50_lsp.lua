-- Defer all vim.lsp and diagnostic setup until first LSP-relevant filetype is opened
-- This avoids loading the entire vim.lsp module chain (~3-5ms) at startup
local lsp_setup_done = false
local bigfile = require("mark.bigfile")
local lazy = require("mark.lazy")
local lsp_servers = require("mark.lsp_servers")
local log = require("mark.log").get("lsp")

vim.api.nvim_create_user_command("LspLogLevel", function(opts)
	vim.lsp.log.set_level(opts.args)
	vim.notify("LSP log level: " .. opts.args, vim.log.levels.INFO)
end, {
	nargs = 1,
	complete = function()
		return { "off", "error", "warn", "info", "debug", "trace" }
	end,
	desc = "Set the Neovim LSP log level",
})

vim.api.nvim_create_user_command("LspLogStatus", function()
	local path = vim.lsp.log.get_filename()
	local stat = vim.uv.fs_stat(path)
	local size = stat and stat.size or 0
	vim.notify(string.format("LSP log: %s (%d bytes)", path, size), vim.log.levels.INFO)
end, { desc = "Show the Neovim LSP log path and size" })

vim.api.nvim_create_user_command("LspLogClear", function(opts)
	if not opts.bang then
		error("Use :LspLogClear! to remove the LSP log")
	end
	local path = vim.lsp.log.get_filename()
	local removed, err = os.remove(path)
	if not removed and err and not err:match("No such file") then
		error(err)
	end
	vim.notify("Removed LSP log: " .. path, vim.log.levels.INFO)
end, { bang = true, desc = "Remove the Neovim LSP log (requires !)" })

local diagnostics_setup_done = false
local function ensure_diagnostics()
	if diagnostics_setup_done then
		return
	end
	diagnostics_setup_done = true

	local diag = icons.diagnostics
	local severity_icons = {
		[vim.diagnostic.severity.ERROR] = diag.error,
		[vim.diagnostic.severity.WARN] = diag.warn,
		[vim.diagnostic.severity.HINT] = diag.hint,
		[vim.diagnostic.severity.INFO] = diag.info,
	}
	local virtual_lines = {
		current_line = true,
		overflow = "auto",
		source = false,
		format = function(diagnostic)
			local message = (severity_icons[diagnostic.severity] or diag.error) .. (diagnostic.message or "")
			if diagnostic.source ~= nil and diagnostic.source ~= "" then
				message = message .. " [" .. tostring(diagnostic.source) .. "]"
			end
			if diagnostic.code ~= nil and diagnostic.code ~= "" then
				message = message .. " (" .. tostring(diagnostic.code) .. ")"
			end
			return message
		end,
	}
	local function virtual_lines_config(_, bufnr)
		if bigfile.is_guarded(bufnr) then
			return false
		end
		return virtual_lines
	end
	vim.diagnostic.config({
		float = {
			source = true,
			max_width = 80,
			max_height = 20,
		},
		severity_sort = true,
		signs = { text = severity_icons },
		virtual_lines = virtual_lines_config,

		-- 0.12+: Configure vim.diagnostic.status() for statusline integration
		status = {
			format = function(counts)
				local parts = {}
				local highlights = {
					[vim.diagnostic.severity.ERROR] = "ErrorMsg",
					[vim.diagnostic.severity.WARN] = "WarningMsg",
					[vim.diagnostic.severity.INFO] = "String",
					[vim.diagnostic.severity.HINT] = "Comment",
				}

				for severity = 1, 4 do
					if counts[severity] then
						table.insert(
							parts,
							string.format(
								"%%#%s#%s%d%%*",
								highlights[severity],
								severity_icons[severity],
								counts[severity]
							)
						)
					end
				end

				return table.concat(parts, " ")
			end,
		},
	})

	local virtual_lines_enabled = true
	vim.keymap.set("n", "<leader>eD", function()
		virtual_lines_enabled = not virtual_lines_enabled
		vim.diagnostic.config({ virtual_lines = virtual_lines_enabled and virtual_lines_config or false })
		vim.notify(
			"Diagnostic virtual lines " .. (virtual_lines_enabled and "enabled" or "disabled"),
			vim.log.levels.INFO
		)
	end, { desc = "Toggle diagnostic virtual lines" })
end

_G._ensure_diagnostics = ensure_diagnostics

local on_type_formatting_enabled_by_client = setmetatable({}, { __mode = "k" })

local function set_linked_editing_enabled(bufnr, enabled)
	vim.b[bufnr].linked_editing_enabled = enabled
	vim.lsp.linked_editing_range.enable(enabled, { bufnr = bufnr })
end

local function client_supports_on_type_formatting(client, bufnr)
	return client and client:supports_method("textDocument/onTypeFormatting", bufnr)
end

local function on_type_formatting_clients(bufnr)
	return vim.lsp.get_clients({
		bufnr = bufnr,
		method = "textDocument/onTypeFormatting",
	})
end

local function set_on_type_formatting_enabled(client, enabled)
	on_type_formatting_enabled_by_client[client] = enabled
	vim.lsp.on_type_formatting.enable(enabled, { client_id = client.id })
end

local document_highlight_group = vim.api.nvim_create_augroup("lsp_document_highlight", { clear = true })

local document_highlight_excluded_clients = {
	nixd = true,
}

local function document_highlight_supported(bufnr)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/documentHighlight" })) do
		if not document_highlight_excluded_clients[client.name] then
			return true
		end
	end
	return false
end

local function clear_document_highlights(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) then
		pcall(vim.api.nvim_buf_call, bufnr, vim.lsp.buf.clear_references)
	end
end

local function configure_document_highlights(bufnr)
	vim.api.nvim_clear_autocmds({ group = document_highlight_group, buf = bufnr })
	vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
		group = document_highlight_group,
		buf = bufnr,
		callback = function(ev)
			if vim.b[ev.buf].document_highlight_enabled ~= false and document_highlight_supported(ev.buf) then
				vim.api.nvim_buf_call(ev.buf, vim.lsp.buf.document_highlight)
			end
		end,
		desc = "Highlight LSP references under the cursor",
	})
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "LspDetach" }, {
		group = document_highlight_group,
		buf = bufnr,
		callback = function(ev)
			clear_document_highlights(ev.buf)
		end,
		desc = "Clear native LSP reference highlights",
	})
	vim.keymap.set("n", "<leader>eH", function()
		local enabled = vim.b[bufnr].document_highlight_enabled == false
		vim.b[bufnr].document_highlight_enabled = enabled
		if enabled and document_highlight_supported(bufnr) then
			vim.api.nvim_buf_call(bufnr, vim.lsp.buf.document_highlight)
		else
			clear_document_highlights(bufnr)
		end
		vim.notify("Document highlight " .. (enabled and "enabled" or "disabled"), vim.log.levels.INFO)
	end, { buf = bufnr, desc = "Toggle Document Highlight" })
end

-- Resolve only the configs needed by filetypes encountered in this session.
-- vim.lsp.enable() eagerly resolves every named config, so enabling the whole
-- allowlist at once adds avoidable work when most sessions use one language.
local server_specs = lsp_servers.specs
local prepared_server_configs = {}

local function prepare_server_config(server)
	if server ~= "gopls" or prepared_server_configs[server] then
		return
	end

	-- Resolve nvim-lspconfig's complete gopls config first so its asynchronous
	-- GOROOT/GOMODCACHE root reuse stays intact for normal Go buffers. Assembly
	-- files use the same config only when a go.work or go.mod owns the file.
	local config = vim.lsp.config[server]
	local inherited_root_dir = config.root_dir
	local filetypes = vim.deepcopy(config.filetypes or {})
	if not vim.list_contains(filetypes, "asm") then
		filetypes[#filetypes + 1] = "asm"
	end

	vim.lsp.config(server, {
		filetypes = filetypes,
		root_dir = function(bufnr, on_dir)
			if vim.bo[bufnr].filetype == "asm" then
				local path = vim.api.nvim_buf_get_name(bufnr)
				local root = path ~= "" and vim.fs.root(path, { "go.work", "go.mod" }) or nil
				if root then
					on_dir(root)
				end
				return
			end

			if type(inherited_root_dir) == "function" then
				return inherited_root_dir(bufnr, on_dir)
			end
			if inherited_root_dir then
				on_dir(inherited_root_dir)
			end
		end,
	})
	prepared_server_configs[server] = true
end

local servers_by_filetype = {}
for _, spec in ipairs(server_specs) do
	for _, filetype in ipairs(spec.filetypes) do
		local servers = servers_by_filetype[filetype] or {}
		servers[#servers + 1] = spec.name
		servers_by_filetype[filetype] = servers
	end
end

local lsp_filetype_patterns = vim.tbl_keys(servers_by_filetype)
table.sort(lsp_filetype_patterns)

local function enable_servers_for_filetype(filetype)
	local servers = servers_by_filetype[filetype]
	if not servers then
		return
	end

	for _, server in ipairs(servers) do
		local ok, err = pcall(function()
			prepare_server_config(server)
			if not vim.lsp.is_enabled(server) then
				vim.lsp.enable(server, true)
			end
		end)
		if not ok then
			-- Keep independent co-servers working when one optional config is
			-- temporarily broken or unavailable.
			log.error("failed to enable LSP config: " .. server, err)
		end
	end
end

-- Load nvim-lspconfig and configure shared behavior once, then resolve only
-- the server configs needed by the requested filetype.
local function lsp_allowed(bufnr, filetype)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	if bigfile.is_guarded(bufnr) then
		return false
	end
	return vim.bo[bufnr].filetype == filetype and servers_by_filetype[filetype] ~= nil
end

local function setup_lsp(filetype, bufnr)
	if bufnr and not lsp_allowed(bufnr, filetype) then
		return
	end
	if lsp_setup_done then
		enable_servers_for_filetype(filetype)
		return
	end

	if not lazy.packadd("nvim-lspconfig", { trigger = "FileType " .. filetype }) then
		return
	end

	-- Server stderr is frequently informational but Neovim records it as errors.
	-- Keep routine sessions quiet and opt into diagnostics with :LspLogLevel.
	vim.lsp.log.set_level("off")
	ensure_diagnostics()

	local function get_blink_capabilities()
		-- Keep blink.cmp lazy: do not require it while starting LSP. Mirror the
		-- capabilities from blink.cmp's public helper so servers still advertise
		-- snippet/resolve support when blink loads later on InsertEnter/CmdlineEnter.
		local blink = package.loaded["blink.cmp"]
		if blink and type(blink.get_lsp_capabilities) == "function" then
			local ok, caps = pcall(blink.get_lsp_capabilities)
			if ok then
				return caps
			end
			log.warn("blink.cmp get_lsp_capabilities failed", caps)
		end

		return {
			textDocument = {
				completion = {
					completionItem = {
						commitCharactersSupport = false,
						preselectSupport = false,
						resolveSupport = {
							properties = { "documentation", "detail", "additionalTextEdits", "command", "data" },
						},
						insertTextModeSupport = { valueSet = { 1 } },
					},
					insertTextMode = 1,
				},
			},
		}
	end

	local capabilities = vim.tbl_deep_extend("force", get_blink_capabilities() or {}, {
		textDocument = {
			foldingRange = {
				rangeLimit = 4096,
			},
		},
	})

	vim.lsp.config("*", {
		capabilities = capabilities,
		exit_timeout = 2000,
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("lsp_attach"),
		callback = function(attach_ev)
			local client = vim.lsp.get_client_by_id(attach_ev.data.client_id)
			if not client then
				return
			end
			if bigfile.is_guarded(attach_ev.buf) then
				pcall(vim.lsp.buf_detach_client, attach_ev.buf, client.id)
				return
			end

			-- Note: document_color is enabled by default in 0.13+

			-- navigation
			vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buf = attach_ev.buf, desc = "Go to Definition" })
			vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buf = attach_ev.buf, desc = "Go to Declaration" })

			-- Neovim 0.12+ features
			vim.keymap.set(
				"n",
				"<leader>cW",
				vim.lsp.buf.workspace_diagnostics,
				{ buf = attach_ev.buf, desc = "Workspace Diagnostics" }
			)

			if client:supports_method("textDocument/linkedEditingRange", attach_ev.buf) then
				-- The buffer-scoped enable state survives client re-attach and goes
				-- away with the buffer. Reapply a prior manual disable on attach.
				if vim.b[attach_ev.buf].linked_editing_enabled == false then
					set_linked_editing_enabled(attach_ev.buf, false)
				end
				vim.keymap.set("n", "<leader>cL", function()
					local enabled = vim.b[attach_ev.buf].linked_editing_enabled == false
					set_linked_editing_enabled(attach_ev.buf, enabled)
					vim.notify("Linked editing " .. (enabled and "enabled" or "disabled"), vim.log.levels.INFO)
				end, { buf = attach_ev.buf, desc = "Toggle Linked Editing" })
			end

			if client_supports_on_type_formatting(client, attach_ev.buf) then
				vim.keymap.set("n", "<leader>eF", function()
					local clients = on_type_formatting_clients(attach_ev.buf)
					if #clients == 0 then
						return
					end

					local all_enabled = true
					for _, attached_client in ipairs(clients) do
						if on_type_formatting_enabled_by_client[attached_client] == false then
							all_enabled = false
							break
						end
					end

					local enable = not all_enabled
					for _, attached_client in ipairs(clients) do
						set_on_type_formatting_enabled(attached_client, enable)
					end
					vim.notify("On-type formatting " .. (enable and "enabled" or "disabled"), vim.log.levels.INFO)
				end, { buf = attach_ev.buf, desc = "Toggle On-Type Formatting" })
			end

			if client:supports_method("textDocument/prepareTypeHierarchy", attach_ev.buf) then
				vim.keymap.set("n", "<leader>ct", function()
					vim.lsp.buf.typehierarchy("supertypes")
				end, { buf = attach_ev.buf, desc = "Type Hierarchy (Supertypes)" })
				vim.keymap.set("n", "<leader>cT", function()
					vim.lsp.buf.typehierarchy("subtypes")
				end, { buf = attach_ev.buf, desc = "Type Hierarchy (Subtypes)" })
			end

			if client:supports_method("textDocument/documentHighlight", attach_ev.buf) then
				configure_document_highlights(attach_ev.buf)
			end
		end,
	})

	-- Global enables: every attaching client gets each feature it supports
	-- (vim/lsp/client.lua _on_attach), and per-buffer toggles override them.
	-- On-type formatting skips clients toggled off with <leader>eF.
	for _, feature in ipairs({ "inline_completion", "inlay_hint", "codelens", "linked_editing_range" }) do
		vim.lsp[feature].enable(true)
	end
	vim.lsp.on_type_formatting.enable(true)

	lsp_setup_done = true
	enable_servers_for_filetype(filetype)

	-- vim.lsp.enable() performs a targeted `doautoall nvim.lsp.enable FileType`
	-- for pre-existing buffers whose FileType fired before this plugin file loaded,
	-- so avoid replaying all FileType handlers and re-sourcing ftplugins.
end

local pending_lsp_filetypes = {}
local function request_lsp_setup(filetype, bufnr)
	if not servers_by_filetype[filetype] or not lsp_allowed(bufnr, filetype) then
		return
	end

	local key = bufnr .. ":" .. filetype
	if pending_lsp_filetypes[key] then
		return
	end
	pending_lsp_filetypes[key] = true

	-- Defer one tick so earlier FileType guards can finish switching minified
	-- buffers to bigfile before any config is enabled for this filetype.
	vim.schedule(function()
		pending_lsp_filetypes[key] = nil
		if lsp_allowed(bufnr, filetype) then
			setup_lsp(filetype, bufnr)
		end
	end)
end

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("lsp_lazy_enable"),
	pattern = lsp_filetype_patterns,
	callback = function(ev)
		request_lsp_setup(ev.match, ev.buf)
	end,
	desc = "Enable only the LSP configs needed by this filetype",
})

-- Handle startup buffers whose FileType fired before plugin/ files loaded.
-- Mirrors the now_if_args pattern used elsewhere for deferred setup, but only
-- for buffers with filetypes that can actually start one of our LSP servers.
now_if_args(function()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local ft = vim.bo[buf].filetype
		if vim.api.nvim_buf_is_loaded(buf) and servers_by_filetype[ft] then
			request_lsp_setup(ft, buf)
		end
	end
end)
