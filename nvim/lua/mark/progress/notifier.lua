local M = {}

function M.setup(context)
	local api = context.api
	local augroup = context.augroup

	local function progress_title(data)
		local id = tostring(data.id or "")
		if vim.startswith(id, "mark.lsp") then
			return "LSP"
		elseif vim.startswith(id, "mark.codecompanion") then
			return "CodeCompanion"
		elseif vim.startswith(id, "mark.neotest") then
			return "Neotest"
		elseif vim.startswith(id, "nvim.bufread ") then
			return "Read"
		elseif vim.startswith(id, "nvim.bufwrite ") then
			return "Write"
		elseif vim.startswith(id, "vim.health") then
			return "Checkhealth"
		end
		return data.title or data.source or "Progress"
	end

	api.nvim_create_autocmd("Progress", {
		group = augroup,
		callback = function(ev)
			if #api.nvim_list_uis() == 0 then
				return
			end
			local snacks = rawget(_G, "Snacks")
			if not (snacks and snacks.notifier) then
				return
			end
			local data = ev.data or {}
			local text = type(data.text) == "table" and table.concat(data.text) or tostring(data.text or "")
			local level = data.status == "failed" and vim.log.levels.ERROR
				or data.status == "cancel" and vim.log.levels.WARN
				or vim.log.levels.INFO
			local timeout
			if data.status == "running" then
				timeout = false
			elseif data.status == "failed" then
				timeout = 9000
			elseif data.status == "cancel" then
				timeout = 5000
			else
				timeout = 1800
			end
			snacks.notifier.notify(text, level, {
				id = "progress:" .. tostring(data.id or data.source or "unknown"),
				title = progress_title(data),
				timeout = timeout,
				history = data.status ~= "running",
			})
		end,
		desc = "Render native progress with Snacks notifier",
	})
end

return M
