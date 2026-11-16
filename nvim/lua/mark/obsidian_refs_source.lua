-- Vault references for Blink completion and Obsidian capture prompts.
--
-- The Blink source only handles @ people in Markdown buffers. Normal [[ note
-- completion remains owned by obsidian.nvim's language server. Capture prompts
-- mirror their text into a hidden vault buffer and ask the same language server
-- for [[ completions.

local LSP_BUF_NAME = ".dotfiles-obsidian-prompt-completion.md"
local LSP_TIMEOUT_MS = 300
local CACHE_MS = 5000

local cache = {}
local lsp_bufs = {}

local function profile()
	return vim.g.dotfiles_obsidian or {}
end

local function normalize_path(path)
	local expanded = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	local normalized = vim.fs.normalize(vim.uv.fs_realpath(expanded) or expanded)
	return normalized == "/" and normalized or normalized:gsub("/+$", "")
end

local function is_within(path, root)
	return path == root or vim.startswith(path, root .. "/")
end

local function workspace_roots()
	local roots = {}
	for _, workspace in ipairs(profile().workspaces or {}) do
		roots[#roots + 1] = normalize_path(workspace.path)
	end
	return roots
end

local function reference_config()
	return profile().references or {}
end

local function capture_config()
	return profile().capture or {}
end

local function references_enabled()
	return reference_config().enabled == true
end

local function people_folder()
	return reference_config().people_folder or "People"
end

local function questions_folder()
	return capture_config().questions_folder or "Questions"
end

---@param path string
---@param fallback boolean|nil
---@return string|nil
local function vault_for_path(path, fallback)
	local roots = workspace_roots()
	if path ~= "" then
		local normalized = normalize_path(path)
		for _, root in ipairs(roots) do
			if is_within(normalized, root) then
				return root
			end
		end
	end
	return fallback and roots[1] or nil
end

local function vault_for_buffer(bufnr)
	local pinned = vim.b[bufnr].dotfiles_obsidian_refs_vault
	if type(pinned) == "string" and pinned ~= "" then
		return normalize_path(pinned)
	end
	return vault_for_path(vim.api.nvim_buf_get_name(bufnr), false)
end

local function read_lines(path, max_lines)
	local file = io.open(path, "r")
	if not file then
		return {}
	end
	local out = {}
	for line in file:lines() do
		out[#out + 1] = line
		if #out >= max_lines then
			break
		end
	end
	file:close()
	return out
end

local function frontmatter(path)
	local lines = read_lines(path, 80)
	local out = { ask = {} }
	if lines[1] ~= "---" then
		return out
	end
	local key
	for index = 2, #lines do
		local line = lines[index]
		if line == "---" then
			break
		end
		local current, value = line:match("^([%w_]+):%s*(.*)$")
		if current then
			key = current
			if current == "type" then
				out.type = vim.trim((value:gsub('^"(.*)"$', "%1")))
			end
		else
			value = line:match("^%s+%-%s*(.*)$")
		end
		if value and key == "ask" then
			for name in value:gmatch("%[%[([^%]|#]+)") do
				out.ask[#out.ask + 1] = vim.trim(name):gsub("^@", "")
			end
		end
	end
	return out
end

local function each_file(root, opts, callback)
	local stat = vim.uv.fs_stat(root)
	if not stat or stat.type ~= "directory" then
		return
	end
	local ok, iterator = pcall(vim.fs.dir, root, opts)
	if not ok or not iterator then
		return
	end
	for relative, kind in iterator do
		if kind == "file" then
			callback(relative)
		end
	end
end

local function people(vault)
	local people_dir = people_folder()
	local questions_dir = questions_folder()
	local cache_key = table.concat({ vault, people_dir, questions_dir }, "\0")
	local cached = cache[cache_key]
	local now = vim.uv.now()
	if cached and now - cached.at < CACHE_MS then
		return cached.people
	end

	local list, seen = {}, {}
	local function add(name)
		name = name and vim.trim(name):gsub("^@", "") or ""
		local key = name:lower()
		if name ~= "" and not seen[key] then
			seen[key] = true
			list[#list + 1] = name
		end
	end

	local people_root = vim.fs.joinpath(vault, people_dir)
	each_file(people_root, nil, function(relative)
		if relative:match("%.md$") then
			add(vim.fs.basename(relative):gsub("%.md$", ""))
		end
	end)

	-- Preserve the downstream behavior without hard-coding its notes root: scan
	-- the parent of the configured people folder for notes marked type: person.
	local search_root = vim.fs.dirname(people_root)
	each_file(search_root, { depth = 4 }, function(relative)
		if relative:match("%.md$") then
			local metadata = frontmatter(vim.fs.joinpath(search_root, relative))
			if metadata.type == "person" then
				add(vim.fs.basename(relative):gsub("%.md$", ""))
			end
		end
	end)

	local questions_root = vim.fs.joinpath(vault, questions_dir)
	each_file(questions_root, nil, function(relative)
		if relative:match("%.md$") then
			for _, name in ipairs(frontmatter(vim.fs.joinpath(questions_root, relative)).ask) do
				add(name)
			end
		end
	end)

	table.sort(list)
	cache[cache_key] = { at = now, people = list }
	return list
end

local function lsp_buffer(vault)
	local bufnr = lsp_bufs[vault]
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		return bufnr
	end
	bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(vault, LSP_BUF_NAME))
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].filetype = "markdown"
	vim.b[bufnr].dotfiles_obsidian_refs_vault = vault
	lsp_bufs[vault] = bufnr
	return bufnr
end

local function obsidian_client(bufnr)
	local client = vim.lsp.get_clients({ bufnr = bufnr, name = "obsidian-ls" })[1]
	if client then
		return client
	end
	local ok, lsp = pcall(require, "obsidian.lsp")
	if not ok then
		return nil
	end
	local client_id = lsp.start(bufnr)
	return client_id and vim.lsp.get_client_by_id(client_id) or nil
end

local function lsp_links(vault, line)
	local bufnr = lsp_buffer(vault)
	local client = obsidian_client(bufnr)
	if not client then
		return {}
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
	local params = {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
		position = { line = 0, character = #line },
		context = { triggerKind = 1 },
	}
	local response = client:request_sync("textDocument/completion", params, LSP_TIMEOUT_MS, bufnr)
	local result = response and response.result
	local items = result and (result.items or result) or {}
	local out = {}
	for _, item in ipairs(items) do
		local edit = item.textEdit
		local text = edit and edit.newText or item.insertText or item.label
		if text and text:match("^%[%[") and not (item.command and item.command.command == "obsidian.write_note") then
			out[#out + 1] = {
				label = item.label,
				insert = text,
				key = text:match("^%[%[[^%]|]+|([^%]]+)%]%]$") or text:match("^%[%[([^%]|]+)") or item.label,
			}
		end
	end
	local query = line:match("%[%[([^%]]*)$") or ""
	if query ~= "" then
		out = vim.fn.matchfuzzy(out, query, { key = "key" })
	end
	return out
end

local M = {}

function M.clear_cache()
	cache = {}
end

function M.enabled()
	return references_enabled()
end

function M.vault_for_path(path, fallback)
	return vault_for_path(path or "", fallback)
end

function M.people(vault)
	return vault and people(normalize_path(vault)) or {}
end

function M.prompt_items(vault, before)
	if not vault or not references_enabled() then
		return { word = "", items = {} }
	end
	vault = normalize_path(vault)
	local link = before:match("(%[%[[^%]]*)$")
	if link then
		local items = {}
		if #link > 2 then
			items = lsp_links(vault, before)
		end
		if #items == 0 then
			for _, person in ipairs(people(vault)) do
				items[#items + 1] = { label = person, insert = "[[" .. person .. "]]" }
			end
		end
		return { word = link, items = items }
	end
	local mention = before:match("(@[^@%[%]%s]*)$")
	if mention and not before:match("[%w._]@[^@%s]*$") then
		local query = mention:sub(2):lower()
		local items = {}
		for _, person in ipairs(people(vault)) do
			if query == "" or person:lower():find(query, 1, true) then
				items[#items + 1] = { label = person, insert = "@" .. person }
			end
		end
		return { word = mention, items = items }
	end
	return { word = "", items = {} }
end

local source = {}

function source.new()
	return setmetatable({}, { __index = source })
end

function source:enabled()
	local bufnr = vim.api.nvim_get_current_buf()
	return references_enabled() and vim.bo[bufnr].filetype == "markdown" and vault_for_buffer(bufnr) ~= nil
end

function source:get_trigger_characters()
	return { "@" }
end

function source:get_completions(ctx, callback)
	local Kind = require("blink.cmp.types").CompletionItemKind
	local vault = vault_for_buffer(ctx.bufnr)
	local before = ctx.line:sub(1, ctx.cursor[2])
	local mention_start = before:match("()@[^@%[%]%s]*$")
	local items = {}
	if
		references_enabled()
		and vault
		and mention_start
		and not (mention_start > 1 and before:sub(mention_start - 1, mention_start - 1):match("[%w._]"))
	then
		local row = ctx.cursor[1] - 1
		local query = before:sub(mention_start + 1):lower()
		for _, person in ipairs(people(vault)) do
			if query == "" or person:lower():find(query, 1, true) then
				items[#items + 1] = {
					label = person,
					filterText = person,
					kind = Kind.Reference,
					labelDetails = { description = "person" },
					textEdit = {
						newText = "[[" .. person .. "]]",
						range = {
							start = { line = row, character = mention_start - 1 },
							["end"] = { line = row, character = ctx.cursor[2] },
						},
					},
				}
			end
		end
	end
	callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

M.new = source.new
M.get_trigger_characters = source.get_trigger_characters
M.get_completions = source.get_completions
M.source = source

return setmetatable(M, { __index = source })
