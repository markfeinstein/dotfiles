return function(context)
  local terminal_creator = context.terminal_creator
  local terminal_shell = context.terminal_shell
  local terminal_command = context.terminal_command
  local rex_cli = context.rex_cli
  local process_cwd = context.process_cwd
  local scratch_label = context.scratch_label or "Scratch Terminal"
  local default_bounds = context.default_bounds or { 0.68, 0.04, 0.30, 0.92 }
  local state_by_session = {}

local function copy_bounds(bounds)
  return { bounds[1], bounds[2], bounds[3], bounds[4] }
end

local function session_state(session_id)
  local state = state_by_session[session_id]
  if state == nil then
    state = { bounds = copy_bounds(default_bounds) }
    state_by_session[session_id] = state
  end
  return state
end

local function view_or_error(session_id)
  local view, err = rex.session.view{ session_id = session_id }
  if view == nil then
    error(err or "unable to inspect the Rex session", 0)
  end
  return view
end

local function active_window(view)
  for _, window in ipairs(view.windows or {}) do
    if window.window_id == view.active_window_id then
      return window
    end
  end
  return nil
end

local function find_layer(view, block_id)
  for _, window in ipairs(view.windows or {}) do
    for _, layer in ipairs(window.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.block_id == block_id then
          return layer, window
        end
      end
    end
  end
  return nil, nil
end

local function tiled_anchor(window)
  for _, layer in ipairs(window.layers or {}) do
    if layer.kind == "tiled" then
      for _, block in ipairs(layer.blocks or {}) do
        if block.block_id == window.focused_block_id then
          return block.block_id
        end
      end
      local first = (layer.blocks or {})[1]
      return first and first.block_id or nil
    end
  end
  return nil
end

local function is_scratch(block)
  return block.label == scratch_label
    and block.creator_name == terminal_creator
    and block.flavor == terminal_shell
end

local function find_scratch(session_id)
  local result, err = rex.session.list_blocks{ session_id = session_id }
  if result == nil then
    error(err or "unable to list Rex panes", 0)
  end

  local state = session_state(session_id)
  local fallback = nil
  local count = 0
  for _, block in ipairs(result.blocks or {}) do
    if is_scratch(block) then
      count = count + 1
      if block.block_id == state.block_id then
        return block
      end
      fallback = fallback or block
    end
  end

  if count > 1 then
    rex.log("warn", string.format("Found %d scratch terminals in %s; using %s", count, session_id, fallback.block_id))
  end
  state.block_id = fallback and fallback.block_id or nil
  return fallback
end

local function focused_cwd(block_id)
  if block_id == nil then
    return nil
  end
  local process = rex.block.call(terminal_creator, "process", { block_id = block_id })
  return process and process_cwd(process) or nil
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function start_terminal(session_id, block_id, cwd)
  local script = ""
  if cwd ~= nil then
    script = "cd -- " .. shell_quote(cwd) .. " && "
  end
  script = script .. "exec " .. shell_quote(terminal_command)
  local helper, helper_err = rex.exec.start({
    "/bin/sh",
    "-c",
    'sleep 0.75; exec "$1" --autostart=false send -s "$2" -b "$3" "$4"',
    "scratch-start",
    rex_cli,
    session_id,
    block_id,
    "exec /bin/sh -c " .. shell_quote(script) .. "\r",
  }, {
    stdout = false,
    stderr = false,
  })
  if helper == nil then
    error(helper_err or "unable to schedule Nushell in the scratch terminal", 0)
  end
end

local function create_scratch(ctx, window, state)
  local options = {
    command = { terminal_command },
    shell = "none",
  }
  local cwd = focused_cwd(ctx.block_id)
  if cwd ~= nil then
    options.cwd = cwd
  end

  local result, err = rex.session.new_layer{
    session_id = ctx.session_id,
    window_id = window.window_id,
    bounds = state.bounds,
    focus = true,
    layout = rex.layout.block{
      flavor = terminal_shell,
      label = scratch_label,
      options = options,
    },
  }
  if result == nil then
    error(err or "unable to create the scratch terminal", 0)
  end
  local block_id = (result.block_ids or {})[1]
  if block_id == nil then
    error("Rex created the scratch terminal without a pane ID", 0)
  end
  state.block_id = block_id
  start_terminal(ctx.session_id, block_id, cwd)
  return {
    block_id = block_id,
    layer_id = result.layer_id,
    visible = true,
  }
end

local function detach(session_id, block_id)
  local result, err = rex.session.detach_block{
    session_id = session_id,
    block_id = block_id,
  }
  if result == nil then
    error(err or "unable to hide the scratch terminal", 0)
  end
end

local function place_and_float(session_id, block_id, window, bounds)
  local anchor_block_id = tiled_anchor(window)
  if anchor_block_id == nil then
    error("the active tab has no tiled pane for the scratch terminal", 0)
  end

  local moved, move_err = rex.session.move_block{
    session_id = session_id,
    block_id = block_id,
    anchor_block_id = anchor_block_id,
    direction = "horizontal",
    side = "after",
    ratio = 0.7,
  }
  if moved == nil then
    error(move_err or "unable to place the scratch terminal", 0)
  end

  local floated, float_err = rex.session.float_block{
    session_id = session_id,
    block_id = block_id,
    bounds = bounds,
  }
  if floated == nil then
    local _, detach_err = rex.session.detach_block{
      session_id = session_id,
      block_id = block_id,
    }
    if detach_err ~= nil then
      float_err = tostring(float_err) .. "; cleanup failed: " .. tostring(detach_err)
    end
    error(float_err or "unable to float the scratch terminal", 0)
  end

  local focused, focus_err = rex.session.focus_block{
    session_id = session_id,
    block_id = block_id,
  }
  if focused == nil then
    error(focus_err or "unable to focus the scratch terminal", 0)
  end
  return floated.layer_id
end

rex.action{
  name = "toggle_scratch_terminal",
  title = "Toggle Scratch Terminal",
  description = "Create, focus, move, or fully hide one floating terminal shared by every tab in this session.",
  category = "Pane",
  keywords = "scratch terminal floating toggle session hide summon",
  run = function(ctx)
    if ctx.session_id == nil then
      error("the scratch terminal needs an active Rex session", 0)
    end

    local state = session_state(ctx.session_id)
    local view = view_or_error(ctx.session_id)
    local window = active_window(view)
    if window == nil then
      error("the Rex session has no active tab", 0)
    end

    local scratch = find_scratch(ctx.session_id)
    if scratch == nil then
      return create_scratch(ctx, window, state)
    end

    local layer, scratch_window = find_layer(view, scratch.block_id)
    if layer ~= nil and layer.bounds ~= nil then
      state.bounds = copy_bounds(layer.bounds)
    end

    if scratch_window ~= nil and scratch_window.window_id == window.window_id then
      if layer.kind == "floating" and layer.state == "minimized" then
        local restored, restore_err = rex.session.set_layer_state{
          session_id = ctx.session_id,
          layer_id = layer.layer_id,
          state = "normal",
          focus = true,
        }
        if restored == nil then
          error(restore_err or "unable to restore the scratch terminal", 0)
        end
        return {
          block_id = scratch.block_id,
          layer_id = layer.layer_id,
          visible = true,
        }
      end

      if window.focused_block_id == scratch.block_id then
        detach(ctx.session_id, scratch.block_id)
        return {
          block_id = scratch.block_id,
          visible = false,
        }
      end

      if layer.kind == "floating" then
        local raised, raise_err = rex.session.raise_layer{
          session_id = ctx.session_id,
          layer_id = layer.layer_id,
        }
        if raised == nil then
          error(raise_err or "unable to raise the scratch terminal", 0)
        end
        local focused, focus_err = rex.session.focus_block{
          session_id = ctx.session_id,
          block_id = scratch.block_id,
        }
        if focused == nil then
          error(focus_err or "unable to focus the scratch terminal", 0)
        end
        return {
          block_id = scratch.block_id,
          layer_id = layer.layer_id,
          visible = true,
        }
      end
    end

    if scratch.placement == "placed" then
      detach(ctx.session_id, scratch.block_id)
    end
    local layer_id = place_and_float(ctx.session_id, scratch.block_id, window, state.bounds)
    return {
      block_id = scratch.block_id,
      layer_id = layer_id,
      visible = true,
    }
  end,
}

end
