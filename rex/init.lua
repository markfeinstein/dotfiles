-- Managed from rex/init.lua and deployed by Home Manager.
-- Rex Beta 0.1.0 configuration: bindings and focused workflow actions,
-- with no remote hosts.

local yabai = "/Applications/Yabai.app/Contents/MacOS/yabai"
local rex_picker = os.getenv("REX_PICKER_PATH") or (os.getenv("HOME") .. "/.local/bin/rex-picker")
local rex_gh_dash = os.getenv("HOME") .. "/.local/bin/rex-gh-dash"
local rex_capture = "@rex_capture@"
local scrollback_editor = "@scrollback_editor@"
local rex_lazygit = os.getenv("HOME") .. "/.local/bin/rex-lazygit"
-- Home Manager replaces this exact default for profiles that enable the
-- personal password-store picker.
local password_picker_enabled = false
local rose_pine_theme = os.getenv("HOME") .. "/.config/rex/themes/Rose Pine"
local rose_pine_moon_theme = os.getenv("HOME") .. "/.config/rex/themes/Rose Pine Moon"
local rose_pine_dawn_theme = os.getenv("HOME") .. "/.config/rex/themes/Rose Pine Dawn"
local rose_pine_dark_theme = rose_pine_theme
local policy_ok, theme_policy = pcall(dofile, os.getenv("HOME") .. "/.config/rex/theme-policy.lua")
if policy_ok and theme_policy.dark_theme ~= nil then
  rose_pine_dark_theme = theme_policy.dark_theme
end
local terminal_creator = "com.superlogical.terminal"
local terminal_shell = "com.superlogical.terminal.shell"
local terminal_drawer_label = "Terminal Drawer"
local terminal_drawer_default_preset = "right"
local terminal_drawer_presets = {
  right = { 0.68, 0.04, 0.30, 0.92 },
  left = { 0.02, 0.04, 0.30, 0.92 },
  center = { 0.15, 0.12, 0.70, 0.76 },
  large = { 0.05, 0.05, 0.90, 0.90 },
}
local terminal_drawer_state_directory = (os.getenv("XDG_STATE_HOME")
  or (os.getenv("HOME") .. "/.local/state")) .. "/rex"
local terminal_drawer_state_path = terminal_drawer_state_directory .. "/terminal-drawer.tsv"
local terminal_drawer_state_header = "# rex-terminal-drawer-state-v2"
local terminal_drawer_state_version = 2
local terminal_native_navigation_blocks = {}

local config_source = debug.getinfo(1, "S").source
local config_path = config_source:sub(1, 1) == "@" and config_source:sub(2) or config_source
local config_directory = config_path:match("^(.*)/[^/]+$") or "."

local function load_relative(path)
  local chunk, err = loadfile(config_directory .. "/" .. path)
  if chunk == nil then
    error(err, 0)
  end
  return chunk()
end

local common = load_relative("lib/common.lua")

local function load_module(name)
  return load_relative("modules/" .. name .. ".lua")
end

local function copy_bounds(bounds)
  return { bounds[1], bounds[2], bounds[3], bounds[4] }
end

local function valid_bounds(bounds)
  if bounds == nil or #bounds ~= 4 then
    return false
  end
  local x, y, width, height = bounds[1], bounds[2], bounds[3], bounds[4]
  return type(x) == "number"
    and type(y) == "number"
    and type(width) == "number"
    and type(height) == "number"
    and x >= 0
    and y >= 0
    and width > 0
    and height > 0
    and x + width <= 1.000001
    and y + height <= 1.000001
end

local drawer_state = load_module("drawer_state")({
  presets = terminal_drawer_presets,
  default_preset = terminal_drawer_default_preset,
  directory = terminal_drawer_state_directory,
  path = terminal_drawer_state_path,
  header = terminal_drawer_state_header,
  version = terminal_drawer_state_version,
  copy_bounds = copy_bounds,
  valid_bounds = valid_bounds,
  write_atomic = common.write_atomic,
})
local terminal_drawer_return_focus_by_session = drawer_state.return_focus_by_session
local terminal_drawer_state = drawer_state.state

local function open_terminal_layer(label, command, bounds, cwd)
  local options = {
    command = command,
    shell = "none",
  }
  if cwd ~= nil then
    options.cwd = cwd
  end

  local result, err = rex.session.new_layer{
    bounds = bounds,
    focus = true,
    layout = rex.layout.block{
      flavor = terminal_shell,
      label = label,
      options = options,
    },
  }
  if result == nil then
    error(err, 0)
  end
  return {
    layer_id = result.layer_id,
    block_ids = result.block_ids or {},
  }
end

local function prefix(key, action, args)
  rex.bind("ctrl+space>" .. key, action, args)
end

-- Match the shared terminal navigation contract. Shells let Rex
-- consume Ctrl-H/J/K/L, while editors and fzf receive the original key.
-- Neovim then crosses a Rex pane only when it reaches an editor split edge.
local editor_processes = {
  fzf = true,
  lvim = true,
  nvi = true,
  nvim = true,
  nvimx = true,
  vi = true,
  view = true,
  vim = true,
  vimx = true,
}
local file_picker_shells = {
  nu = true,
  nushell = true,
  zsh = true,
}

local function normalized_process_name(process)
  if process == nil then
    return nil
  end

  local name = process.script or process.argv0 or process.name
  if name == nil then
    return nil
  end

  name = name:match("([^/]+)$") or name
  name = name:gsub("^-", "")
  name = name:gsub("%-wrapped$", "")
  name = name:gsub("diff$", "")
  if editor_processes[name] then
    return name
  end

  local without_g = name:match("^g%.?(.+)$")
  if without_g ~= nil and editor_processes[without_g] then
    return without_g
  end

  return name
end

local function terminal_owns_navigation(ctx)
  local block_id = ctx and ctx.block_id or nil
  if block_id ~= nil and terminal_native_navigation_blocks[block_id] then
    return true, nil
  end

  local process, err = rex.block.call(terminal_creator, "process")
  if process == nil then
    return nil, err
  end

  local name = normalized_process_name(process.foreground)
  return name ~= nil and editor_processes[name] == true, nil
end

local function active_block_id(view)
  local window = common.active_window(view)
  return window and window.focused_block_id or nil
end

local function terminal_drawer_anchor_block_id(session_id, view)
  local window = common.active_window(view)
  local remembered_block_id = terminal_drawer_return_focus_by_session[session_id]
  if remembered_block_id ~= nil then
    for _, layer in ipairs(window and window.layers or {}) do
      if layer.kind == "tiled" then
        for _, block in ipairs(layer.blocks or {}) do
          if block.block_id == remembered_block_id then
            return remembered_block_id
          end
        end
      end
    end
  end
  return common.tiled_block_id(window)
end

load_module("navigation")({
  yabai = yabai,
  terminal_creator = terminal_creator,
  terminal_shell = terminal_shell,
  terminal_drawer_label = terminal_drawer_label,
  terminal_drawer_return_focus_by_session = terminal_drawer_return_focus_by_session,
  terminal_owns_navigation = terminal_owns_navigation,
  active_block_id = active_block_id,
  active_window = common.active_window,
  prefix = prefix,
})

local drawer = load_module("drawer")({
  terminal_creator = terminal_creator,
  terminal_shell = terminal_shell,
  terminal_drawer_label = terminal_drawer_label,
  terminal_drawer_presets = terminal_drawer_presets,
  terminal_drawer_return_focus_by_session = terminal_drawer_return_focus_by_session,
  copy_bounds = copy_bounds,
  terminal_drawer_state = terminal_drawer_state,
  update_terminal_drawer_state = drawer_state.update,
  active_window = common.active_window,
  active_block_id = active_block_id,
  terminal_drawer_anchor_block_id = terminal_drawer_anchor_block_id,
  tiled_block_id = common.tiled_block_id,
  move_and_float = common.move_and_float,
  process_cwd = common.process_cwd,
})

load_module("geometry")({
  copy_bounds = copy_bounds,
  find_block_layer = drawer.find_block_layer,
  layer_contains_terminal_drawer = drawer.layer_contains_terminal_drawer,
  update_terminal_drawer_state = drawer.update_terminal_drawer_state,
  view_or_error = drawer.view_or_error,
})

load_module("pickers")({
  terminal_creator = terminal_creator,
  terminal_shell = terminal_shell,
  editor_processes = editor_processes,
  file_picker_shells = file_picker_shells,
  normalized_process_name = normalized_process_name,
  open_terminal_layer = open_terminal_layer,
  terminal_native_navigation_blocks = terminal_native_navigation_blocks,
  process_cwd = common.process_cwd,
  write_atomic = common.write_atomic,
  rex_picker = rex_picker,
  rex_gh_dash = rex_gh_dash,
  rex_capture = rex_capture,
  scrollback_editor = scrollback_editor,
  rex_lazygit = rex_lazygit,
  password_picker_enabled = password_picker_enabled,
  rose_pine_theme = rose_pine_theme,
  rose_pine_moon_theme = rose_pine_moon_theme,
  rose_pine_dawn_theme = rose_pine_dawn_theme,
  rose_pine_dark_theme = rose_pine_dark_theme,
})

load_module("bindings")({
  prefix = prefix,
  password_picker_enabled = password_picker_enabled,
  terminal_drawer_default_preset = terminal_drawer_default_preset,
})
