-- Run through the configured nightly entry point with an isolated HOME.
local ok, err = pcall(function()
	assert(vim.version().prerelease, "the editor must remain on Neovim nightly")
	assert(vim.v.errmsg == "", "startup error: " .. vim.v.errmsg)
	assert(require("mark.treesitter").ensure_runtime())

	local grammars = vim.json.decode(table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_GRAMMARS), "\n"))
	for _, language in ipairs(grammars) do
		local paths = vim.fn.globpath(
			vim.o.packpath,
			"pack/*/start/nvim-treesitter-grammars/parser/" .. language .. ".so",
			false,
			true
		)
		assert(#paths > 0, "cached parser package is missing: " .. language)
		-- Use a fresh alias so a bundled nightly parser cannot mask the cached one.
		local alias = "cached_" .. language
		assert(vim.treesitter.language.add(alias, { path = paths[1], symbol_name = language }))
		local parser = vim.treesitter.get_string_parser("", alias)
		assert(#parser:parse() > 0, "cannot parse with cached grammar: " .. language)
		assert(vim.treesitter.language.add(language), "cannot load runtime parser: " .. language)
		for _, group in ipairs({ "highlights", "injections", "folds", "textobjects", "indents" }) do
			-- Missing query groups are fine; incompatible queries raise an error.
			vim.treesitter.query.get(language, group)
		end
	end

	local optional = vim.fn.globpath(vim.o.packpath, "pack/*/opt/*", false, true)
	for _, path in ipairs(optional) do
		vim.cmd.packadd(vim.fs.basename(path))
	end
	for _, module in ipairs({ "flash", "snacks", "oil", "blink.cmp", "codediff", "nvim-treesitter" }) do
		assert(require(module), "cannot load cached plugin: " .. module)
	end
	assert(vim.v.errmsg == "", "plugin error: " .. vim.v.errmsg)
	print(
		string.format("PASS: nightly loaded %d cached grammars and %d optional plugin packages", #grammars, #optional)
	)
end)

if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
