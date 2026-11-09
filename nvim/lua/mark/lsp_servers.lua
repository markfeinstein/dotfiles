local M = {}

local tooling = vim.g.dotfiles_neovim_tooling or {}
local all_specs = {
	{ name = "bashls", filetypes = { "bash", "sh", "zsh" } },
	{ name = "buf_ls", filetypes = { "proto", "buf-config" }, tooling = "infrastructure" },
	{ name = "cssls", filetypes = { "css", "scss", "less" }, tooling = "web" },
	{
		name = "docker_language_server",
		filetypes = { "dockerfile", "yaml.docker-compose" },
		tooling = "infrastructure",
	},
	{ name = "gopls", filetypes = { "go", "gomod", "gowork", "gotmpl", "asm" }, tooling = "go" },
	{ name = "html", filetypes = { "html" }, tooling = "web" },
	{
		name = "htmx",
		filetypes = {
			"astro",
			"heex",
			"html",
			"htmlangular",
			"htmldjango",
			"javascriptreact",
			"php",
			"svelte",
			"templ",
			"typescriptreact",
			"vue",
		},
		tooling = "web",
	},
	{ name = "jsonls", filetypes = { "json", "jsonc" }, tooling = "web" },
	{ name = "lua_ls", filetypes = { "lua" } },
	{ name = "marksman", filetypes = { "markdown" } },
	{ name = "nushell", filetypes = { "nu" } },
	{ name = "rust_analyzer", filetypes = { "rust" }, tooling = "rust" },
	{ name = "sqls", filetypes = { "mysql", "plsql", "sql" }, tooling = "sql" },
	{
		name = "tailwindcss",
		filetypes = {
			"astro",
			"css",
			"heex",
			"html",
			"htmlangular",
			"htmldjango",
			"javascript",
			"javascriptreact",
			"less",
			"markdown",
			"php",
			"sass",
			"scss",
			"svelte",
			"templ",
			"typescript",
			"typescriptreact",
			"vue",
		},
		tooling = "web",
	},
	{
		name = "terraformls",
		filetypes = { "hcl", "terraform", "terraform-vars" },
		tooling = "infrastructure",
	},
	{
		name = "ts_ls",
		filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
		tooling = "web",
	},
	{ name = "yamlls", filetypes = { "yaml", "yaml.docker-compose" } },
	{ name = "nixd", filetypes = { "nix" } },
}

M.specs = {}
for _, spec in ipairs(all_specs) do
	if spec.tooling == nil or tooling[spec.tooling] then
		M.specs[#M.specs + 1] = spec
	end
end

M.filetypes = {}
for _, spec in ipairs(M.specs) do
	M.filetypes[spec.name] = spec.filetypes
end

return M
