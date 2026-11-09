-- render-markdown.nvim: load after the first markdown/codecompanion paint.
local lazy = require("mark.lazy")

-- Plugin setup loads runtime files and configures parsers. Keep it out of
-- BufReadPre/FileType so the buffer and statusline can draw first.
do
	local setup_queued = false
	local function queue_render_markdown()
		if setup_queued then
			return
		end
		setup_queued = true
		later(function()
			setup_queued = false
			require("mark.render_markdown").ensure()
		end)
	end

	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("render_markdown_lazy"),
		pattern = { "markdown", "codecompanion" },
		callback = queue_render_markdown,
		desc = "Load render-markdown after the first paint",
	})
end

-- lazydev.nvim: deferred to first Lua buffer.
-- Keep a startup replay for buffers whose FileType fired before registration.
do
	local function setup_lazydev()
		if vim.g._lazydev_loaded then
			return true
		end
		vim.g._lazydev_loaded = true
		lazy.packadd("lazydev.nvim", { trigger = "FileType lua" })
		local lazydev = lazy.require("lazydev", { notify = true })
		if not lazydev then
			vim.g._lazydev_loaded = false
			return false
		end
		lazydev.setup({
			library = {
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
				{ path = "snacks.nvim", words = { "Snacks" } },
				{ path = "mini.nvim", words = { "Mini" } },
			},
		})
	end
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("lazydev_lazy_load"),
		pattern = "lua",
		once = true,
		callback = setup_lazydev,
		desc = "Load lazydev.nvim for Lua buffers",
	})

	now_if_args(function()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.bo[buf].filetype == "lua" then
				setup_lazydev()
				break
			end
		end
	end)
end

-- flash.nvim - Enhanced Motion
-- Provided by Nix; loaded on first keymap trigger.

do
	local loaded = false
	local function ensure_flash()
		if not loaded then
			require("flash").setup({ modes = { char = { jump_labels = true } } })
			loaded = true
		end
	end
	-- Note: mini.ai owns an/in (next textobject), overriding Neovim's default
	-- incremental selection maps; ]n/[n stay native. Flash.nvim treesitter mode
	-- still available via :Flash.
	vim.keymap.set("o", "r", function()
		ensure_flash()
		require("flash").remote()
	end, { desc = "Remote Flash" })
end

-- dial.nvim - Enhanced Increment/Decrement

local dial_loaded = false
local function ensure_dial()
	if dial_loaded then
		return true
	end
	if not lazy.packadd("dial.nvim", { notify = true, trigger = "increment/decrement keymap" }) then
		return false
	end

	local augend = lazy.require("dial.augend", { notify = true })
	local config = lazy.require("dial.config", { notify = true })
	if not augend or not config then
		return false
	end

	local filetype_augends = {
		json = {
			augend.integer.alias.decimal,
			augend.constant.alias.bool,
		},
		lua = {
			augend.integer.alias.decimal,
			augend.constant.alias.bool,
		},
		markdown = {
			augend.misc.alias.markdown_header,
		},
	}

	config.augends:register_group(vim.tbl_extend("force", {
		default = {
			augend.constant.alias.alpha,
			augend.constant.alias.Alpha,
			augend.constant.alias.bool,
			augend.constant.alias.Bool,
			augend.date.alias["%Y/%m/%d"],
			augend.integer.alias.decimal,
			augend.integer.alias.hex,
			augend.misc.alias.markdown_header,
			augend.semver.alias.semver,
			augend.constant.new({ elements = { "&&", "||" }, word = false }),
			augend.constant.new({
				elements = {
					"january",
					"february",
					"march",
					"april",
					"may",
					"june",
					"july",
					"august",
					"september",
					"october",
					"november",
					"december",
				},
				preserve_case = true,
			}),
			augend.constant.new({
				elements = {
					"first",
					"second",
					"third",
					"fourth",
					"fifth",
					"sixth",
					"seventh",
					"eighth",
					"ninth",
					"tenth",
				},
				word = false,
				preserve_case = true,
			}),
			augend.constant.new({
				elements = { "enable", "disable" },
				preserve_case = true,
			}),
			augend.constant.new({
				elements = { "enabled", "disabled" },
				preserve_case = true,
			}),
			augend.constant.new({
				elements = { "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday" },
				preserve_case = true,
			}),
		},
	}, filetype_augends))

	config.augends:on_filetype(filetype_augends)
	dial_loaded = true
	return true
end

local function dial(direction, mode)
	return function()
		if ensure_dial() then
			require("dial.map").manipulate(direction, mode)
		end
	end
end

vim.keymap.set("n", "<C-a>", dial("increment", "normal"), { desc = "Increment" })
vim.keymap.set("n", "<C-x>", dial("decrement", "normal"), { desc = "Decrement" })
vim.keymap.set("v", "<C-a>", dial("increment", "visual"), { desc = "Increment" })
vim.keymap.set("v", "<C-x>", dial("decrement", "visual"), { desc = "Decrement" })
