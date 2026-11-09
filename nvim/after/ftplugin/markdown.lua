local set = vim.opt_local

set.linebreak = false

vim.keymap.set("n", "<leader>mp", function()
	require("mark.render_markdown").ensure()
	if vim.fn.exists(":RenderMarkdown") == 2 then
		vim.cmd("RenderMarkdown preview")
	else
		vim.notify("RenderMarkdown command is unavailable", vim.log.levels.WARN)
	end
end, { buf = 0, desc = "Markdown Preview" })
