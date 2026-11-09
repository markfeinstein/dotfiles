local M = {}

local cache

local function load()
	if cache then
		return cache
	end

	local path = vim.env.DOTFILES_THEME_FILE
	if not path or path == "" then
		local source = debug.getinfo(1, "S").source:sub(2)
		-- Resolve the store-managed configuration before locating its packaged
		-- copy of the repository-wide canonical palette.
		source = vim.uv.fs_realpath(source) or source
		local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
		path = vim.fs.joinpath(root, "themes", "rose-pine.json")
	end
	local file, open_error = io.open(path, "r")
	if not file then
		error(("unable to open shared palette %s: %s"):format(path, open_error), 0)
	end

	local content = file:read("*a")
	file:close()
	local ok, decoded = pcall(vim.json.decode, content)
	if not ok then
		error(("unable to decode shared palette %s: %s"):format(path, decoded), 0)
	end

	cache = decoded
	return cache
end

function M.variant(name)
	local data = load()
	local variant = data.variants and data.variants[name]
	if not variant then
		error(("shared palette variant is missing: %s"):format(name), 0)
	end
	return {
		colorSpace = data.canonicalColorSpace or "srgb",
		colors = variant.colors,
		derived = (data.derived and data.derived[name]) or {},
		terminal = variant.terminal,
	}
end

return M
