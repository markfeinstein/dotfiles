local M = {}

local injected_format_filetypes = {
	angular = true,
	astro = true,
	codecompanion = true,
	gotmpl = true,
	heex = true,
	html = true,
	htmlangular = true,
	markdown = true,
	octo = true,
	svelte = true,
	templ = true,
	vue = true,
}

function M.cleanup_formatters(bufnr)
	local formatters = { "trim_newlines", "trim_whitespace" }
	if injected_format_filetypes[vim.bo[bufnr or 0].filetype] then
		formatters[#formatters + 1] = "injected"
	end
	return formatters
end

local tooling = vim.g.dotfiles_neovim_tooling or {}
local formatters_by_ft = {
	["_"] = { lsp_format = "first" },
	["*"] = M.cleanup_formatters,
	lua = { "stylua" },
	nix = { "alejandra" },
	nu = { "nufmt" },
	sh = { "shfmt" },
}

if tooling.go then
	formatters_by_ft.go = { "goimports-reviser", "gofumpt" }
end
if tooling.rust then
	formatters_by_ft.rust = { "rustfmt" }
end
if tooling.web then
	for _, filetype in ipairs({
		"css",
		"html",
		"javascript",
		"javascriptreact",
		"json",
		"jsonc",
		"typescript",
		"typescriptreact",
		"yaml",
	}) do
		formatters_by_ft[filetype] = { "prettier" }
	end
end

M.opts = {
	default_format_opts = { lsp_format = "fallback" },
	formatters = {
		gofumpt = {
			env = { GOFUMPT_SPLIT_LONG_LINES = "on" },
		},
		["goimports-reviser"] = {
			args = { "-separate-named", "-set-alias", "-use-cache", "$FILENAME" },
		},
	},
	formatters_by_ft = formatters_by_ft,
}

function M.should_format_on_save(filetype)
	return filetype ~= "_" and filetype ~= "*" and M.opts.formatters_by_ft[filetype] ~= nil
end

return M
