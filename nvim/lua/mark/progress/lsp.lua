local M = {}

function M.setup(context)
	local api = context.api
	local augroup = context.augroup
	local log = require("mark.log").get("ui_progress")
	local native_progress = context.native_progress
	local rex_program_status = context.rex_program_status

	local lsp_progress = _G._lsp_progress_state or {}
	_G._lsp_progress_state = lsp_progress
	lsp_progress.tasks = lsp_progress.tasks or {}
	lsp_progress.next_seq = lsp_progress.next_seq or 0

	local function current_lsp_progress()
		local tasks = {}
		local numeric_count, percent_total = 0, 0
		for _, task in pairs(lsp_progress.tasks) do
			local text = task.client .. ": " .. task.title
			if task.percentage then
				text = text .. " " .. task.percentage .. "%"
				percent_total = percent_total + math.max(0, math.min(100, task.percentage))
				numeric_count = numeric_count + 1
			end
			if task.message and task.message ~= "" then
				text = text .. " — " .. task.message
			end
			tasks[#tasks + 1] = { text = text, updated = task.updated or 0 }
		end
		table.sort(tasks, function(a, b)
			if a.updated ~= b.updated then
				return a.updated > b.updated
			end
			return a.text < b.text
		end)
		local percent = numeric_count > 0 and math.floor(percent_total / numeric_count + 0.5) or nil
		local primary = tasks[1]
		local text = primary and primary.text or nil
		if text and #tasks > 1 then
			text = text .. string.format(" (+%d more)", #tasks - 1)
		end
		return text, percent, #tasks
	end

	local function update_lsp_progress(finished_name)
		local text, percent, task_count = current_lsp_progress()
		if task_count == 0 then
			if lsp_progress.native_active then
				native_progress("LSP", finished_name .. ": Ready", "success", 100)
				lsp_progress.native_active = nil
				lsp_progress.native_text = nil
				lsp_progress.native_percent = nil
			end
			if lsp_progress.rex_active then
				rex_program_status({ state = "clear", id = "nvim/lsp" })
				lsp_progress.rex_active = nil
			end
			return
		end

		if text ~= lsp_progress.native_text or percent ~= lsp_progress.native_percent then
			lsp_progress.native_active = native_progress("LSP", text, "running", percent) or lsp_progress.native_active
			lsp_progress.native_text = text
			lsp_progress.native_percent = percent
		end
		lsp_progress.rex_active = rex_program_status({
			state = "working",
			id = "nvim/lsp",
			app = "nvim",
			title = "LSP",
			message = text,
			progress = percent,
		}) or lsp_progress.rex_active
	end

	api.nvim_create_autocmd("VimLeavePre", {
		group = augroup,
		callback = function()
			if lsp_progress.native_active then
				native_progress("LSP", "LSP canceled", "cancel", 100)
				lsp_progress.native_active = nil
			end
			if lsp_progress.rex_active then
				rex_program_status({ state = "clear", id = "nvim/lsp" })
				lsp_progress.rex_active = nil
			end
		end,
	})

	api.nvim_create_autocmd("LspProgress", {
		group = augroup,
		callback = function(ev)
			local params = ev.data and ev.data.params
			local value = params and params.value
			if type(value) ~= "table" then
				log.warn("LspProgress event missing progress value", ev.data)
				return
			end
			local client_id = ev.data and ev.data.client_id
			local client = client_id and vim.lsp.get_client_by_id(client_id) or nil
			local name = client and client.name or "LSP"
			local task_key = tostring(client_id) .. "\0" .. tostring(params.token)

			if value.kind == "begin" then
				lsp_progress.next_seq = lsp_progress.next_seq + 1
				lsp_progress.tasks[task_key] = {
					client = name,
					title = value.title or "",
					message = value.message or "",
					percentage = value.percentage,
					updated = lsp_progress.next_seq,
				}
			elseif value.kind == "report" then
				local task = lsp_progress.tasks[task_key]
				if task then
					lsp_progress.next_seq = lsp_progress.next_seq + 1
					task.updated = lsp_progress.next_seq
					task.message = value.message or task.message
					if value.percentage ~= nil then
						task.percentage = value.percentage
					end
				end
			elseif value.kind == "end" then
				lsp_progress.tasks[task_key] = nil
			end

			update_lsp_progress(name)
		end,
	})
end

return M
