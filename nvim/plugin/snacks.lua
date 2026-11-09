local setup_snacks = require("mark.snacks").setup

local function open_terminal()
	require("snacks").terminal.open()
end

local snacks_keymaps = {
	{
		mode = "n",
		lhs = "<c-/>",
		rhs = open_terminal,
		desc = "Open Floating Terminal",
	},
	{
		mode = "n",
		lhs = "<c-;>",
		rhs = open_terminal,
		desc = "Open Floating Terminal",
	},
	{
		mode = "n",
		lhs = "<c-_>",
		rhs = open_terminal,
		desc = "which_key_ignore",
	},
	{ mode = "n", lhs = "<C-e>", rhs = "<Cmd>DismissMsg<CR>", desc = "Dismiss all notifications" },
	{
		mode = "n",
		lhs = "<leader>bd",
		rhs = function()
			require("snacks").bufdelete()
		end,
		desc = "Delete buffer",
	},
	{
		mode = "n",
		lhs = "<leader>cR",
		rhs = function()
			require("snacks").rename.rename_file()
		end,
		desc = "Rename file",
	},
	{
		mode = "n",
		lhs = "<leader>gY",
		rhs = function()
			require("snacks").gitbrowse.open()
		end,
		desc = "Copy Git Permalink",
	},
}

local snacks_toggles = {
	-- Built-in toggles
	{ type = "dim", name = "Dimming", map = "<leader>em" },
	{ type = "indent", name = "Indent Guides", map = "<leader>eg" },
	{ type = "treesitter", name = "Treesitter Highlighting", map = "<leader>eT" },
	{ type = "zoom", name = "Zoom Mode", map = "<leader>eZ" },
	{ type = "diagnostics", name = "Diagnostics", map = "<leader>ed" },
	{ type = "line_number", name = "Line Numbers", map = "<leader>el" },
	{ type = "inlay_hints", name = "Inlay Hints", map = "<leader>eh" },

	-- Option toggles
	{ type = "option", option = "spell", opts = { name = "Spelling" }, map = "<leader>es" },
	{ type = "option", option = "wrap", opts = { name = "Wrap" }, map = "<leader>ew" },
	{
		type = "option",
		option = "relativenumber",
		opts = { name = "Relative Line Numbers" },
		map = "<leader>eL",
	},
	{
		type = "option",
		option = "conceallevel",
		opts = { off = 0, on = 2, name = "Concealment" },
		map = "<leader>ec",
	},
	{
		type = "option",
		option = "showtabline",
		opts = { off = 0, on = (vim.o.showtabline > 0 and vim.o.showtabline or 2), name = "Tab Bar" },
		map = "<leader>eA",
	},

	-- Custom toggles
	{
		type = "custom",
		opts = {
			name = "Format on Save",
			get = function()
				return vim.g.format_on_save
			end,
			set = function()
				vim.g.format_on_save = not vim.g.format_on_save
				return vim.g.format_on_save
			end,
		},
		map = "<leader>ef",
	},
	{
		type = "custom",
		opts = {
			name = "Go Lint on Save",
			get = function()
				return vim.g.golangci_lint_on_save
			end,
			set = function(state)
				vim.g.golangci_lint_on_save = state
			end,
		},
		map = "<leader>eq",
	},
	{
		type = "custom",
		opts = {
			name = "Git Diff Signs",
			get = function()
				return not vim.b.minidiff_disable
			end,
			set = function()
				local buf = vim.api.nvim_get_current_buf()
				if vim.b.minidiff_disable then
					MiniDiff.enable(buf)
				else
					MiniDiff.disable(buf)
				end
				return not vim.b.minidiff_disable
			end,
		},
		map = "<leader>eG",
	},
}

local function ensure_snacks()
	return setup_snacks()
end

local function toggle_desc(t)
	local name = t.name or (t.opts and t.opts.name) or t.option or t.type
	return "Toggle " .. tostring(name):gsub("_", " "):gsub("^%l", string.upper)
end

local toggle_cache = {}
local function toggle_for(t)
	local cached = toggle_cache[t.map]
	if cached then
		return cached
	end
	ensure_snacks()
	local snacks_toggle = require("snacks.toggle")
	local toggle_obj
	if t.type == "option" then
		toggle_obj = snacks_toggle.option(t.option, t.opts or {})
	elseif t.type == "custom" then
		toggle_obj = snacks_toggle(t.opts)
	else
		local method = snacks_toggle[t.type]
		if type(method) == "function" then
			toggle_obj = method()
		end
	end
	if toggle_obj then
		toggle_cache[t.map] = toggle_obj
	end
	return toggle_obj
end

vim.api.nvim_create_user_command("Zen", function()
	ensure_snacks()
	require("snacks.toggle").zen():toggle()
end, { desc = "Toggle Zen Mode" })

-- Register keymaps directly
for _, km in ipairs(snacks_keymaps) do
	local modes = km.mode
	local rhs = km.rhs
	if type(rhs) == "function" then
		vim.keymap.set(modes, km.lhs, function(...)
			ensure_snacks()
			return rhs(...)
		end, { desc = km.desc })
	else
		vim.keymap.set(modes, km.lhs, rhs, { desc = km.desc })
	end
end

for _, t in ipairs(snacks_toggles) do
	vim.keymap.set("n", t.map, function()
		local toggle_obj = toggle_for(t)
		if toggle_obj then
			toggle_obj:toggle()
		end
	end, { desc = toggle_desc(t) })
end
