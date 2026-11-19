-- Run from the wrapper before init.lua enables vim.loader, not via require():
-- the module loader being configured must not load this bootstrap from cache.
-- Nix preserves source mtimes, so same-size edits behind ~/.config/nvim can
-- otherwise match old bytecode. A new immutable config target gets a new cache;
-- restarting or rolling back to the same target reuses its existing cache.
do
	local config = vim.fn.stdpath("config")
	local resolved = vim.uv.fs_realpath(config) or config
	-- vim.loader.path is an internal API. The native-loader regression tests
	-- must keep verifying that the packaged Neovim actually honors this field.
	vim.loader.path = vim.fs.joinpath(vim.fn.stdpath("cache"), "luac", vim.fn.sha256(resolved))
end
