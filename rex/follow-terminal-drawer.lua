-- Keep a visible floating Terminal Drawer in the active Rex tab and handle
-- workflow events that configuration files cannot receive. Run with:
--   rex do /path/to/follow-terminal-drawer.lua --all
-- Stop the watcher with Ctrl-C. Detached, docked, and minimized drawers stay
-- where they are; only a visible floating drawer follows tab changes.

local terminal_creator = "com.superlogical.terminal"
local terminal_shell = "com.superlogical.terminal.shell"
local terminal_drawer_label = "Terminal Drawer"
local rex_state_directory = (os.getenv("XDG_STATE_HOME")
  or (os.getenv("HOME") .. "/.local/state")) .. "/rex"
local terminal_drawer_state_path = rex_state_directory .. "/terminal-drawer.tsv"
local file_picker_focus_directory = rex_state_directory .. "/file-picker-focus"
local follow_delay_seconds = 0.025
local pending_by_session = {}
local moving_by_session = {}

local script_source = debug.getinfo(1, "S").source
local script_path = script_source:sub(1, 1) == "@" and script_source:sub(2) or script_source
local script_directory = script_path:match("^(.*)/[^/]+$") or "."
local common_chunk, common_err = loadfile(script_directory .. "/lib/common.lua")
if common_chunk == nil then
  error(common_err, 0)
end
local common = common_chunk()

local function remembered_drawer_block_id(session_id)
  local file = io.open(terminal_drawer_state_path, "r")
  if file == nil then
    return nil
  end

  for line in file:lines() do
    if line:sub(1, 1) ~= "#" then
      local saved_session_id, _, _, _, _, _, block_id = line:match(
        "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$"
      )
      if saved_session_id == session_id then
        file:close()
        if block_id ~= nil and block_id ~= "-" then
          return block_id
        end
        return nil
      end
    end
  end

  file:close()
  return nil
end

local function visible_floating_drawer(view, session_id)
  local remembered_block_id = remembered_drawer_block_id(session_id)
  local fallback_block = nil
  local fallback_layer = nil
  local fallback_window = nil

  for _, window in ipairs(view.windows or {}) do
    for _, layer in ipairs(window.layers or {}) do
      if layer.kind == "floating" and layer.state ~= "minimized" then
        for _, block in ipairs(layer.blocks or {}) do
          if block.creator_name == terminal_creator and block.flavor == terminal_shell then
            if remembered_block_id ~= nil and block.block_id == remembered_block_id then
              return block, layer, window
            end
            if fallback_block == nil and block.label == terminal_drawer_label then
              fallback_block = block
              fallback_layer = layer
              fallback_window = window
            end
          end
        end
      end
    end
  end

  return fallback_block, fallback_layer, fallback_window
end

local function log_failure(message, err)
  rex.log("warn", message .. ": " .. tostring(err))
end

local function file_picker_focus_path(block_id)
  local safe_block_id = block_id:gsub("[^%w._-]", "_")
  return file_picker_focus_directory .. "/" .. safe_block_id .. ".tsv"
end

local function restore_file_picker_focus(event)
  local path = file_picker_focus_path(event.block_id)
  local file = io.open(path, "r")
  if file == nil then
    return
  end

  local line = file:read("*l")
  file:close()
  os.remove(path)
  local session_id, block_id = (line or ""):match("^([^\t]+)\t([^\t]+)$")
  if session_id == nil or block_id == nil then
    rex.log("warn", "Ignoring invalid file picker focus state for " .. tostring(event.block_id))
    return
  end

  local focused, focus_err = rex.session.focus_block{
    session_id = session_id,
    block_id = block_id,
  }
  if focused == nil then
    log_failure("Unable to restore focus after closing the file picker", focus_err)
  end
end

local function follow_drawer(session_id)
  if moving_by_session[session_id] then
    return
  end

  local view, view_err = rex.session.view{ session_id = session_id }
  if view == nil then
    log_failure("Unable to inspect the Rex session while following the terminal drawer", view_err)
    return
  end

  local target_window = common.active_window(view)
  local drawer, layer, drawer_window = visible_floating_drawer(view, session_id)
  if target_window == nil
    or drawer == nil
    or drawer_window.window_id == target_window.window_id
  then
    return
  end

  local anchor_block_id = common.tiled_block_id(target_window)
  if anchor_block_id == nil then
    rex.log("warn", "Unable to follow the terminal drawer: the active tab has no tiled pane")
    return
  end

  local return_focus_block_id = target_window.focused_block_id
  local moving_drawer_will_steal_focus = drawer_window.focused_block_id == drawer.block_id
  moving_by_session[session_id] = true

  local floated, stage, move_err = common.move_and_float({
    session_id = session_id,
    block_id = drawer.block_id,
    anchor_block_id = anchor_block_id,
    bounds = layer.bounds,
  })
  if floated == nil then
    moving_by_session[session_id] = nil
    local message = stage == "move" and "Unable to move the terminal drawer into the active tab"
      or "Unable to float the terminal drawer in the active tab"
    log_failure(message, move_err)
    return
  end

  if moving_drawer_will_steal_focus
    and return_focus_block_id ~= nil
    and return_focus_block_id ~= drawer.block_id
  then
    local focused, focus_err = rex.session.focus_block{
      session_id = session_id,
      block_id = return_focus_block_id,
    }
    if focused == nil then
      log_failure("Unable to restore focus after following the terminal drawer", focus_err)
    end
  end

  moving_by_session[session_id] = nil
end

local function schedule_follow(session_id)
  local pending = pending_by_session[session_id]
  if pending ~= nil then
    pending:cancel()
  end

  pending_by_session[session_id] = rex.after(follow_delay_seconds, function()
    pending_by_session[session_id] = nil
    local ok, err = pcall(follow_drawer, session_id)
    moving_by_session[session_id] = nil
    if not ok then
      log_failure("Terminal drawer follow failed", err)
    end
  end)
end

rex.on("block_closed", function(_, event)
  restore_file_picker_focus(event)
end)

rex.on("active_window_changed", function(ctx)
  if ctx.session_id ~= nil then
    schedule_follow(ctx.session_id)
  end
end)

rex.on("session_destroyed", function(_, ev)
  local pending = pending_by_session[ev.session_id]
  if pending ~= nil then
    pending:cancel()
    pending_by_session[ev.session_id] = nil
  end
  moving_by_session[ev.session_id] = nil
end)
