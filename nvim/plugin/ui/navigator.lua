--- Unified navigation for Rex and the native window manager. At the edge of
--- Vim splits, one keybind (ctrl+h/j/k/l) moves between editor splits, terminal
--- panes, and native windows.

local is_rex = vim.env.REX_SESSION ~= nil and vim.env.REX_SESSION ~= ""

local direction_name = { h = "left", j = "down", k = "up", l = "right" }
local wm_dir = { h = "west", j = "south", k = "north", l = "east" }

local navigation_generation = 0

-- vim.system() throws when an executable cannot run; callers fall back instead.
local function run(args, token, callback)
	local function complete(result)
		if not callback then
			return
		end

		vim.schedule(function()
			if token == navigation_generation then
				callback(result)
			end
		end)
	end

	local ok = pcall(vim.system, args, { timeout = 1000 }, complete)
	if not ok then
		complete(nil)
	end
end

local function vim_navigate(direction)
	local ok, err = pcall(vim.cmd.wincmd, direction)
	if not ok then
		vim.api.nvim_echo({ { tostring(err), "ErrorMsg" } }, false)
	end
end

local function focus_native_window(direction, token)
	if vim.fn.executable("yabai") == 1 then
		run({ "yabai", "-m", "window", "--focus-robust", wm_dir[direction] }, token)
	end
end

local function rex_focused_block(result)
	if not result or result.code ~= 0 then
		return nil
	end

	local ok, decoded = pcall(vim.json.decode, result.stdout or "")
	if not ok or type(decoded) ~= "table" or type(decoded.windows) ~= "table" then
		return nil
	end

	for _, window in ipairs(decoded.windows) do
		if window.window_id == decoded.active_window_id then
			return window.focused_block_id
		end
	end

	return nil
end

local function focus_rex_or_native(direction, token)
	if vim.fn.executable("rex") ~= 1 then
		focus_native_window(direction, token)
		return
	end

	local inspect = { "rex", "session", "inspect", vim.env.REX_SESSION, "--json" }
	run(inspect, token, function(before_result)
		local before = rex_focused_block(before_result)
		if before == nil then
			focus_native_window(direction, token)
			return
		end

		run({ "rex", "focus", "-s", vim.env.REX_SESSION, direction_name[direction] }, token, function(focus_result)
			if not focus_result or focus_result.code ~= 0 then
				focus_native_window(direction, token)
				return
			end

			run(inspect, token, function(after_result)
				local after = rex_focused_block(after_result)
				if after == nil then
					-- Focus may already have moved to another Rex pane. Avoid a
					-- second, native-window move when verification is inconclusive.
					return
				end
				if after == before then
					focus_native_window(direction, token)
				end
			end)
		end)
	end)
end

local function navigate(direction)
	navigation_generation = navigation_generation + 1
	local token = navigation_generation
	local win_before = vim.api.nvim_get_current_win()
	vim_navigate(direction)

	if win_before ~= vim.api.nvim_get_current_win() then
		return
	end

	if is_rex then
		focus_rex_or_native(direction, token)
	else
		focus_native_window(direction, token)
	end
end

-- Preserve Neovim's public CTRL-L default before CTRL-L becomes pane
-- navigation, then expose it on terminals with enhanced CTRL+SHIFT input.
local ctrl_l_default = vim.fn.maparg("<C-L>", "n", false, true)
if ctrl_l_default.rhs then
	vim.keymap.set("n", "<C-S-l>", ctrl_l_default.rhs, { desc = ctrl_l_default.desc })
end

local navigation_modes = is_rex and { "n", "i", "t" } or { "n", "i" }
for key, name in pairs({ h = "Left", j = "Down", k = "Up", l = "Right" }) do
	vim.api.nvim_create_user_command("Navigate" .. name, function()
		navigate(key)
	end)
	vim.keymap.set(
		navigation_modes,
		"<C-" .. key .. ">",
		"<cmd>Navigate" .. name .. "<cr>",
		{ desc = "Navigate " .. name }
	)
end
