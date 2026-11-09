local timer = require("mark.timer")

local M = {}

local METHOD = "textDocument/documentSymbol"

local cache = {}
local states = {}
local version = 0

local function bump_version()
	version = version + 1
end

local function get_state(bufnr)
	local state = states[bufnr]
	if not state then
		state = { generation = 0 }
		states[bufnr] = state
	end
	return state
end

local function clear_cache(bufnr)
	if cache[bufnr] ~= nil then
		cache[bufnr] = nil
		bump_version()
	end
end

local function evict_failed_client(bufnr, client_id)
	local per_client = cache[bufnr]
	if not per_client or per_client[client_id] == nil then
		return false
	end
	per_client[client_id] = nil
	if vim.tbl_isempty(per_client) then
		cache[bufnr] = nil
	end
	return true
end

local function prune_cache(bufnr, clients)
	local per_client = cache[bufnr]
	if not per_client then
		return
	end
	local active = {}
	for _, client in ipairs(clients or {}) do
		active[client.id or 0] = true
	end
	local changed = false
	for client_id in pairs(per_client) do
		if not active[client_id] then
			per_client[client_id] = nil
			changed = true
		end
	end
	if changed then
		if vim.tbl_isempty(per_client) then
			cache[bufnr] = nil
		end
		bump_version()
	end
end

local function supported_clients(lsp, bufnr)
	local result = lsp.get_clients({
		bufnr = bufnr,
		method = METHOD,
	})
	table.sort(result, function(a, b)
		return (a.id or 0) < (b.id or 0)
	end)
	return result
end

local function make_key(bufnr, clients)
	local ids = {}
	for i, client in ipairs(clients) do
		ids[i] = tostring(client.id or 0)
	end
	return table.concat(
		{ vim.api.nvim_buf_get_name(bufnr), tostring(vim.api.nvim_buf_get_changedtick(bufnr)), table.concat(ids, ",") },
		"\0"
	)
end

local function clear_request_state(state, completed_key)
	state.in_flight_key = nil
	state.completed_key = completed_key
	state.had_success = nil
	state.pending_clients = nil
	state.pending_count = nil
end

local function finish_request_state(state, key)
	clear_request_state(state, state.had_success and key or nil)
end

local function finish_response(state, key, gen, client_id, success)
	if state.generation ~= gen or state.in_flight_key ~= key then
		return false
	end
	if state.pending_clients then
		state.pending_clients[client_id] = nil
		state.pending_count = math.max(0, (state.pending_count or 1) - 1)
	end
	if success then
		state.had_success = true
	end
	if (state.pending_count or 0) > 0 then
		return true
	end
	finish_request_state(state, key)
	return true
end

local function normalize_symbols(result)
	if result == nil or result == vim.NIL or type(result) ~= "table" then
		return {}
	end
	return result
end

local function start_request(bufnr, key, clients, opts)
	local lsp = package.loaded["vim.lsp"]
	if not lsp or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local state = get_state(bufnr)
	state.generation = state.generation + 1
	local gen = state.generation
	state.in_flight_key = key
	state.pending_key = nil
	state.pending_clients = {}
	state.pending_count = #clients
	state.had_success = false
	prune_cache(bufnr, clients)
	local requested_name = vim.api.nvim_buf_get_name(bufnr)
	local requested_tick = vim.api.nvim_buf_get_changedtick(bufnr)
	local clients_by_id = {}
	for _, client in ipairs(clients) do
		local client_id = client.id or 0
		state.pending_clients[client_id] = true
		clients_by_id[client_id] = client
	end

	local params = { textDocument = lsp.util.make_text_document_params(bufnr) }
	local function handle_response(err, result, ctx)
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		if state.generation ~= gen or state.in_flight_key ~= key then
			return
		end
		if vim.api.nvim_buf_get_name(bufnr) ~= requested_name then
			return
		end
		if vim.api.nvim_buf_get_changedtick(bufnr) ~= requested_tick then
			return
		end
		local client_id = (ctx and ctx.client_id) or 0
		if state.pending_clients and not state.pending_clients[client_id] then
			return
		end
		local success = err == nil
		local cache_changed = false
		if success then
			cache[bufnr] = cache[bufnr] or {}
			local client = clients_by_id[client_id]
			cache[bufnr][client_id] = {
				symbols = normalize_symbols(result),
				position_encoding = client and client.offset_encoding or "utf-16",
			}
			cache_changed = true
		else
			cache_changed = evict_failed_client(bufnr, client_id)
		end
		if cache_changed then
			bump_version()
		end
		if finish_response(state, key, gen, client_id, success) and cache_changed and opts and opts.on_update then
			opts.on_update(bufnr)
		end
	end

	local request_ids = {}
	local ok_request = pcall(function()
		for _, client in ipairs(clients) do
			local sent, request_id = client:request(METHOD, params, handle_response, bufnr)
			if sent then
				request_ids[client.id or 0] = request_id
			end
		end
	end)
	if not ok_request then
		local cache_changed = false
		for _, client in ipairs(clients) do
			cache_changed = evict_failed_client(bufnr, client.id or 0) or cache_changed
		end
		clear_request_state(state, nil)
		if cache_changed then
			bump_version()
			if opts and opts.on_update then
				opts.on_update(bufnr)
			end
		end
		return
	end

	if state.generation ~= gen or state.in_flight_key ~= key then
		return
	end
	local cache_changed = false
	for client_id in pairs(state.pending_clients or {}) do
		if not request_ids[client_id] then
			cache_changed = evict_failed_client(bufnr, client_id) or cache_changed
			state.pending_clients[client_id] = nil
			state.pending_count = math.max(0, (state.pending_count or 1) - 1)
		end
	end
	if (state.pending_count or 0) == 0 then
		finish_request_state(state, key)
	end
	if cache_changed then
		bump_version()
		if opts and opts.on_update then
			opts.on_update(bufnr)
		end
	end
end

function M.schedule(bufnr, delay_ms, opts)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local lsp = package.loaded["vim.lsp"]
	if not lsp then
		clear_cache(bufnr)
		return
	end
	local clients = supported_clients(lsp, bufnr)
	if #clients == 0 then
		clear_cache(bufnr)
		return
	end
	prune_cache(bufnr, clients)
	local state = get_state(bufnr)
	local key = make_key(bufnr, clients)
	if state.completed_key == key or state.in_flight_key == key or state.pending_key == key then
		return
	end
	state.pending_key = key
	timer.replace(states, bufnr .. ":timer", delay_ms or 0, function()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		local fresh_lsp = package.loaded["vim.lsp"]
		if not fresh_lsp then
			clear_cache(bufnr)
			return
		end
		local fresh_clients = supported_clients(fresh_lsp, bufnr)
		if #fresh_clients == 0 then
			clear_cache(bufnr)
			return
		end
		prune_cache(bufnr, fresh_clients)
		local fresh_key = make_key(bufnr, fresh_clients)
		if state.pending_key ~= fresh_key then
			return
		end
		if state.completed_key == fresh_key or state.in_flight_key == fresh_key then
			state.pending_key = nil
			return
		end
		start_request(bufnr, fresh_key, fresh_clients, opts)
	end)
end

function M.prune(bufnr)
	local lsp = package.loaded["vim.lsp"]
	if not lsp or not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		clear_cache(bufnr)
		return
	end
	prune_cache(bufnr, supported_clients(lsp, bufnr))
end

function M.invalidate(bufnr)
	local state = states[bufnr]
	if state then
		state.generation = state.generation + 1
		clear_request_state(state, nil)
		state.pending_key = nil
		timer.cancel_slot(states, bufnr .. ":timer")
	end
	clear_cache(bufnr)
end

function M.cleanup(bufnr)
	M.invalidate(bufnr)
	states[bufnr] = nil
end

function M.cache_for(bufnr)
	return cache[bufnr]
end

function M.version()
	return version
end

return M
