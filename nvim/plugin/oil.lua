local function allow_git_operation()
	return true
end

local oil_opts = {
	columns = { "icon", "size", "mtime" },
	win_options = { wrap = true, signcolumn = "yes" },
	delete_to_trash = true,
	skip_confirm_for_simple_edits = true,
	prompt_save_on_select_new_entry = false,
	lsp_file_methods = { autosave_changes = true },
	constrain_cursor = "name",
	watch_for_changes = true,
	keymaps = {
		["?"] = "actions.show_help",
		["<CR>"] = "actions.select",
		["<C-y>"] = "actions.copy_entry_path",
		["<C-Y>"] = "actions.copy_entry_filename",
		["<C-v>"] = { "actions.select", opts = { vertical = true } },
		["<C-s>"] = { "actions.select", opts = { horizontal = true } },
		["<C-t>"] = { "actions.select", opts = { tab = true } },
		["<C-r>"] = "actions.refresh",
		["<C-q>"] = "actions.add_to_qflist",
		["-"] = "actions.parent",
		["_"] = "actions.open_cwd",
		["`"] = "actions.cd",
		["~"] = { "actions.cd", opts = { scope = "tab" } },
		["K"] = "actions.preview",
		["<C-n>"] = "actions.preview_scroll_down",
		["<C-f>"] = "actions.preview_scroll_down",
		["<C-p>"] = "actions.preview_scroll_up",
		["s"] = "actions.change_sort",
		["q"] = "actions.close",
		["."] = "actions.toggle_hidden",
		["\\"] = "actions.toggle_trash",
	},
	use_default_keymaps = false,
	view_options = { show_hidden = true },
	git = {
		add = allow_git_operation,
		mv = allow_git_operation,
		rm = allow_git_operation,
	},
	float = {
		override = function(conf)
			conf.col = math.floor((vim.o.columns - conf.width) / 2)
			return conf
		end,
	},
}

require("oil").setup(oil_opts)

vim.keymap.set("n", "-", function()
	require("oil").open_float(nil, { preview = {} })
end, { desc = "Open File Browser" })
