local M = {}

M.specs = {
	{ name = "bashls", filetypes = { "bash", "sh", "zsh" } },
	{ name = "buf_ls", filetypes = { "proto", "buf-config" } },
	{ name = "cssls", filetypes = { "css", "scss", "less" } },
	{ name = "docker_language_server", filetypes = { "dockerfile", "yaml.docker-compose" } },
	{ name = "gopls", filetypes = { "go", "gomod", "gowork", "gotmpl", "asm" } },
	{ name = "html", filetypes = { "html" } },
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
	},
	{ name = "jsonls", filetypes = { "json", "jsonc" } },
	{ name = "lua_ls", filetypes = { "lua" } },
	{ name = "marksman", filetypes = { "markdown" } },
	{ name = "nushell", filetypes = { "nu" } },
	{ name = "rust_analyzer", filetypes = { "rust" } },
	{ name = "sqls", filetypes = { "mysql", "plsql", "sql" } },
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
	},
	{ name = "terraformls", filetypes = { "hcl", "terraform", "terraform-vars" } },
	{
		name = "ts_ls",
		filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
	},
	{ name = "yamlls", filetypes = { "yaml", "yaml.docker-compose" } },
	{ name = "nixd", filetypes = { "nix" } },
}

M.filetypes = {}
for _, spec in ipairs(M.specs) do
	M.filetypes[spec.name] = spec.filetypes
end

return M
