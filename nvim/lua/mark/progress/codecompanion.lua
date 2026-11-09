local M = {}

function M.setup(context)
	local api = context.api
	local augroup = context.augroup
	local timer = require("mark.timer")
	local native_progress = context.native_progress
	local rex_program_status = context.rex_program_status

	-- CodeCompanion LLM request progress — one sticky notification for all active
	-- requests. Uses public CodeCompanion User events and does not load the plugin.
	local codecompanion_progress = _G._codecompanion_progress or {}
	_G._codecompanion_progress = codecompanion_progress
	codecompanion_progress.requests = codecompanion_progress.requests or {}
	codecompanion_progress.spinner_index = codecompanion_progress.spinner_index or 0
	codecompanion_progress.next_seq = codecompanion_progress.next_seq or 0
	timer.cancel_slot(codecompanion_progress, "spinner_timer")

	local codecompanion_spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

	local function codecompanion_request_key(data)
		if data and data.id ~= nil then
			return tostring(data.id)
		end
		return nil
	end

	local function codecompanion_adapter_label(data)
		local adapter = data and data.adapter or {}
		local name = adapter.formatted_name or adapter.name or "LLM"
		local model = adapter.model
		if type(model) == "function" then
			local ok, result = pcall(model, adapter)
			model = ok and result or nil
		end
		if model ~= nil and tostring(model) ~= "" then
			return tostring(name) .. " (" .. tostring(model) .. ")"
		end
		return tostring(name)
	end

	local function codecompanion_active_count()
		return vim.tbl_count(codecompanion_progress.requests)
	end

	local function codecompanion_sorted_requests()
		local items = {}
		for _, request in pairs(codecompanion_progress.requests) do
			items[#items + 1] = request
		end
		table.sort(items, function(a, b)
			return (a.seq or 0) < (b.seq or 0)
		end)
		return items
	end

	local function codecompanion_progress_text()
		local items = codecompanion_sorted_requests()
		local count = #items
		local frame = codecompanion_spinner[(codecompanion_progress.spinner_index % #codecompanion_spinner) + 1]
		if count == 1 then
			local request = items[1]
			return string.format("%s CodeCompanion: %s — %s", frame, request.state or "waiting", request.label)
		end

		local lines = { string.format("%s CodeCompanion: %d active requests", frame, count) }
		for _, request in ipairs(items) do
			lines[#lines + 1] = string.format("- %s: %s", request.state or "waiting", request.label)
		end
		return table.concat(lines, "\n")
	end

	local function codecompanion_running_percent()
		for _, request in pairs(codecompanion_progress.requests) do
			if request.state == "streaming" then
				return 50
			end
		end
		return 0
	end

	local function codecompanion_rex_status(state, message, progress)
		return rex_program_status({
			state = state,
			id = "nvim/codecompanion",
			app = "codecompanion",
			title = "CodeCompanion",
			message = message,
			progress = progress,
		})
	end

	local function codecompanion_schedule_spinner()
		timer.replace(codecompanion_progress, "spinner_timer", 120, function()
			if codecompanion_active_count() == 0 then
				return
			end
			codecompanion_progress.spinner_index = codecompanion_progress.spinner_index + 1
			native_progress("CodeCompanion", codecompanion_progress_text(), "running", codecompanion_running_percent())
			codecompanion_schedule_spinner()
		end)
	end

	local function codecompanion_refresh_progress()
		if codecompanion_active_count() == 0 then
			timer.cancel_slot(codecompanion_progress, "spinner_timer")
			return
		end

		local text = codecompanion_progress_text()
		local percent = codecompanion_running_percent()
		native_progress("CodeCompanion", text, "running", percent)
		codecompanion_rex_status("working", text:gsub("^%S+%s+", "", 1), percent)
		codecompanion_schedule_spinner()
	end

	local codecompanion_terminal_priority = {
		success = 1,
		unknown = 2,
		cancel = 3,
		error = 4,
	}

	-- CodeCompanion 19.25 finishes requests with success, error, or cancelled
	-- (http.lua, acp/prompt_builder.lua, interactions/cli/init.lua). The finish
	-- path re-normalizes the aggregate status, so "cancel" must map to itself.
	local codecompanion_status_aliases = {
		success = "success",
		error = "error",
		cancelled = "cancel",
		cancel = "cancel",
	}

	local codecompanion_finish_metadata = {
		success = { "CodeCompanion request completed", "success" },
		error = { "CodeCompanion request failed", "failed" },
		cancel = { "CodeCompanion request canceled", "cancel" },
		unknown = { "CodeCompanion request finished with unknown status", "failed" },
	}

	local function codecompanion_terminal_status(status)
		return status and codecompanion_status_aliases[status] or "unknown"
	end

	local function codecompanion_record_terminal_status(status)
		local terminal_status = codecompanion_terminal_status(status)
		local current_status = codecompanion_progress.terminal_status
		if
			current_status == nil
			or (codecompanion_terminal_priority[terminal_status] or 0)
				> (codecompanion_terminal_priority[current_status] or 0)
		then
			codecompanion_progress.terminal_status = terminal_status
		end
		return codecompanion_progress.terminal_status
	end

	local function codecompanion_finish_details(status)
		return unpack(codecompanion_finish_metadata[codecompanion_terminal_status(status)])
	end

	local function codecompanion_finish_progress(status)
		timer.cancel_slot(codecompanion_progress, "spinner_timer")
		local message, native_status = codecompanion_finish_details(status)

		native_progress("CodeCompanion", message, native_status, 100)
		codecompanion_rex_status(({ success = "done", failed = "error", cancel = "idle" })[native_status], message)

		codecompanion_progress.requests = {}
		codecompanion_progress.terminal_status = nil
	end

	local function codecompanion_ensure_request(data)
		local key = codecompanion_request_key(data)
		if not key then
			return nil, false
		end
		if codecompanion_active_count() == 0 then
			codecompanion_progress.terminal_status = nil
		end
		local request = codecompanion_progress.requests[key]
		local created = false
		if not request then
			codecompanion_progress.next_seq = codecompanion_progress.next_seq + 1
			request = { seq = codecompanion_progress.next_seq }
			codecompanion_progress.requests[key] = request
			created = true
		end
		return request, created
	end

	api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionRequestStarted",
		group = augroup,
		callback = function(ev)
			local data = ev.data or {}
			local request = codecompanion_ensure_request(data)
			if not request then
				return
			end
			request.state = request.state or "waiting"
			request.label = codecompanion_adapter_label(data)
			codecompanion_refresh_progress()
		end,
	})

	api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionRequestStreaming",
		group = augroup,
		callback = function(ev)
			local data = ev.data or {}
			local request, created = codecompanion_ensure_request(data)
			if not request then
				return
			end
			if created or data.adapter then
				request.label = codecompanion_adapter_label(data)
			end
			request.state = "streaming"
			codecompanion_refresh_progress()
		end,
	})

	api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionRequestFinished",
		group = augroup,
		callback = function(ev)
			local data = ev.data or {}
			local key = codecompanion_request_key(data)
			local tracked_request = key and codecompanion_progress.requests[key] ~= nil
			local terminal_status = codecompanion_progress.terminal_status
			if tracked_request or not key or codecompanion_active_count() == 0 then
				terminal_status = codecompanion_record_terminal_status(data.status)
			end
			if key then
				codecompanion_progress.requests[key] = nil
			end
			if codecompanion_active_count() > 0 then
				codecompanion_refresh_progress()
			else
				codecompanion_finish_progress(terminal_status)
			end
		end,
	})

	api.nvim_create_autocmd("VimLeavePre", {
		group = augroup,
		callback = function()
			if codecompanion_active_count() > 0 then
				native_progress("CodeCompanion", "CodeCompanion request canceled", "cancel", 100)
				codecompanion_rex_status("idle", "CodeCompanion request canceled")
			end
			timer.cancel_slot(codecompanion_progress, "spinner_timer")
			codecompanion_progress.requests = {}
			codecompanion_progress.terminal_status = nil
		end,
	})

	if codecompanion_active_count() > 0 then
		codecompanion_refresh_progress()
	end
end

return M
