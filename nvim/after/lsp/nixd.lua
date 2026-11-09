local buffer_path = vim.api.nvim_buf_get_name(0)
local start_path = buffer_path == "" and vim.uv.cwd() or vim.fs.dirname(buffer_path)
local dotfiles_root = vim.fs.root(start_path, "flake.nix") or vim.env.DOTFILES_ROOT

if not dotfiles_root then
	return {}
end

local flake = "git+" .. vim.uri.from_fname(dotfiles_root)
local arch = jit.arch == "arm64" and "aarch64" or "x86_64"
local os = jit.os == "OSX" and "darwin" or "linux"
local system = vim.env.NIX_SYSTEM or vim.env.NIXPKGS_SYSTEM or (arch .. "-" .. os)
local profile = vim.env.DOTFILES_NIX_PROFILE or "personal"
local options

if os == "darwin" then
	options = {
		darwin = {
			expr = ("(builtins.getFlake %q).darwinConfigurations.%q.options"):format(flake, profile),
		},
		home_manager = {
			expr = ("(builtins.getFlake %q).darwinConfigurations.%q.options.home-manager.users.type.getSubOptions []"):format(
				flake,
				profile
			),
		},
	}
else
	local configuration = ("%s-%s"):format(system, profile)
	options = {
		home_manager = {
			expr = ("(builtins.getFlake %q).homeConfigurations.%q.options"):format(flake, configuration),
		},
	}
end

return {
	settings = {
		nixd = {
			nixpkgs = {
				expr = ("import (builtins.getFlake %q).inputs.nixpkgs { system = %q; }"):format(flake, system),
			},
			options = options,
		},
	},
}
