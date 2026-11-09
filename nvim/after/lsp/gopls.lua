--- https://github.com/golang/tools/tree/master/gopls

local build_flags = vim.env.GOPLS_BUILD_FLAGS

-- root_dir and the base filetypes come from nvim-lspconfig. plugin/50_lsp.lua
-- wraps that resolved root callback before adding asm, preserving GOROOT and
-- GOMODCACHE reuse while requiring a Go workspace for assembly files.
return {
	cmd = { "gopls", "-remote=auto", "-remote.listen.timeout=5m" },
	cmd_env = {
		GOFUMPT_SPLIT_LONG_LINES = "on",
	},
	settings = {
		gopls = {
			-- Build flags can be customized via GOPLS_BUILD_FLAGS env var (comma-separated tags)
			-- Example: export GOPLS_BUILD_FLAGS="integration,debug"
			-- Default: empty (no build flags)
			buildFlags = build_flags ~= nil and build_flags ~= "" and { "-tags=" .. build_flags } or {},
			analyses = {
				shadow = true,
			},
			codelenses = {
				test = true,
				tidy = false,
				upgrade_dependency = false,
				vendor = false,
			},
			directoryFilters = {
				"-.devcontainer",
				"-.git",
				"-.github",
				"-.idea",
				"-.vscode",
				"-.vscode-test",
				"-acl",
				"-build",
				"-config/external",
				"-**/node_modules",
			},
			gofumpt = true,
			hints = {
				assignVariableTypes = true,
				compositeLiteralFields = true,
				compositeLiteralTypes = true,
				constantValues = true,
				functionTypeParameters = true,
				ignoredError = true,
				parameterNames = true,
				rangeVariableTypes = true,
			},
			-- Explicit false disables all Staticcheck analyzers; omission enables gopls' subset.
			staticcheck = false,
			templateExtensions = {
				"tmpl",
				"tpl",
			},
			usePlaceholders = true,
		},
	},
}
