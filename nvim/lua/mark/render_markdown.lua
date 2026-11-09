local M = {}
local lazy = require("mark.lazy")

local setup_done = false
local failed = false

local function warn_once(message)
	if failed then
		return
	end
	failed = true
	pcall(vim.notify, message, vim.log.levels.WARN)
	local log = require("mark.log").get("render-markdown")
	log.warn(message)
end

local function config()
	local md = icons.markdown
	return {
		file_types = { "markdown", "codecompanion" },
		debounce = 300,
		restart_highlighter = true,
		checkbox = {
			custom = {
				in_progress = { raw = "[~]", rendered = md.in_progress, highlight = "RenderMarkdownTodo" },
				important = { raw = "[!]", rendered = md.important, highlight = "RenderMarkdownError" },
				cancelled = { raw = "[-]", rendered = md.cancelled, highlight = "RenderMarkdownError" },
				forwarded = { raw = "[>]", rendered = md.forwarded, highlight = "RenderMarkdownHint" },
			},
		},
		code = { width = "block", right_pad = 1 },
		completions = { lsp = { enabled = true } },
	}
end

function M.ensure()
	if setup_done then
		return true
	end

	local ok, err = xpcall(function()
		assert(lazy.packadd("render-markdown.nvim", { log = false, trigger = "deferred FileType/Markdown preview" }))
		local render_markdown = assert(lazy.require("render-markdown", { log = false }))
		render_markdown.setup(config())
	end, debug.traceback)

	if ok then
		setup_done = true
		return true
	end

	warn_once("render-markdown.nvim failed to load; opening Markdown without rendering: " .. tostring(err))
	return false
end

return M
