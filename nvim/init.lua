-- Capture timing baselines before anything else runs.
vim.g.start_hrtime = vim.uv.hrtime()

-- Profile-owned flags and paths must exist before plugin runtime files load.
require("mark.profile")

-- Enable byte-compilation cache for faster require() calls
vim.loader.enable()

-- Disable some built-in plugins; the Nix wrapper owns provider disables and
-- Oil's setup (default_file_explorer) disables netrw. Keep the nvim.dir plugin:
-- Oil renames directory buffers before it acts, and the zip browser uses its maps.
vim.g.loaded_tutor_mode_plugin = 1
vim.g.loaded_gzip = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_matchit = 1

vim.g.loaded_remote_plugins = 1

-- Register image read handlers before startup opens the first user buffer.
-- Individual Snacks modules still load on their configured events.
require("mark.snacks").setup()

vim.cmd.colorscheme("rose_pine")
