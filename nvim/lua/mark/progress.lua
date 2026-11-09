local api = vim.api

local M = {}

local function rex_text(value, max_chars)
	local text = tostring(value or ""):gsub("[%c]", " "):gsub("%s+", " ")
	return vim.base64.encode(vim.fn.strcharpart(text, 0, max_chars))
end

local function rex_program_status(opts)
	if vim.env.REX_SESSION == nil or vim.env.REX_SESSION == "" then
		return false
	end

	local fields = { "state=" .. opts.state, "id=" .. opts.id }
	if opts.state ~= "clear" then
		fields[#fields + 1] = "app=" .. opts.app
		fields[#fields + 1] = "title=" .. rex_text(opts.title, 48)
		fields[#fields + 1] = "msg=" .. rex_text(opts.message, 512)
		if opts.progress ~= nil and (opts.state == "working" or opts.state == "blocked") then
			fields[#fields + 1] = "progress=" .. math.max(0, math.min(100, math.floor(opts.progress)))
		end
	end

	local sequence = "\27]7501;" .. table.concat(fields, ":") .. "\27\\"
	return pcall(api.nvim_ui_send, sequence)
end

local native_progress_ids = { LSP = "mark.lsp", CodeCompanion = "mark.codecompanion" }

local function native_progress(source, text, status, percent)
	return pcall(api.nvim_echo, { { text } }, status ~= "running", {
		kind = "progress",
		id = native_progress_ids[source],
		source = source,
		title = source,
		status = status,
		percent = percent,
	})
end

function M.setup()
	local context = {
		api = api,
		augroup = api.nvim_create_augroup("ui_progress"),
		native_progress = native_progress,
		rex_program_status = rex_program_status,
	}

	require("mark.progress.notifier").setup(context)
	require("mark.progress.lsp").setup(context)
	if vim.g.dotfiles_neovim_ai_enabled then
		require("mark.progress.codecompanion").setup(context)
	end
end

return M
