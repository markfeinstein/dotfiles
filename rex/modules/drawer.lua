return function(context)
  local terminal_creator = context.terminal_creator
  local terminal_shell = context.terminal_shell
  local terminal_drawer_label = context.terminal_drawer_label
  local terminal_drawer_presets = context.terminal_drawer_presets
  local terminal_drawer_return_focus_by_session = context.terminal_drawer_return_focus_by_session
  local copy_bounds = context.copy_bounds
  local terminal_drawer_state = context.terminal_drawer_state
  local update_terminal_drawer_state = context.update_terminal_drawer_state
  local active_window = context.active_window
  local active_block_id = context.active_block_id
  local terminal_drawer_anchor_block_id = context.terminal_drawer_anchor_block_id
  local tiled_block_id = context.tiled_block_id
  local move_and_float = context.move_and_float
  local process_cwd = context.process_cwd

local function view_or_error(session_id)
  local view, err = rex.session.view{ session_id = session_id }
  if view == nil then
    error(err or "unable to inspect the Rex session", 0)
  end
  return view
end

local function find_block_layer(view, block_id)
  for _, window in ipairs(view.windows or {}) do
    for _, layer in ipairs(window.layers or {}) do
      for index, block in ipairs(layer.blocks or {}) do
        if block.block_id == block_id then
          return layer, index
        end
      end
    end
  end
  return nil, nil
end

local function is_terminal_drawer(block)
  return block ~= nil
    and block.label == terminal_drawer_label
    and block.creator_name == terminal_creator
    and block.flavor == terminal_shell
end

local function find_terminal_drawer(session_id)
  local result, err = rex.session.list_blocks{ session_id = session_id }
  if result == nil then
    error(err or "unable to list Rex panes", 0)
  end

  local state = terminal_drawer_state(session_id)
  if state.block_id ~= nil then
    for _, block in ipairs(result.blocks or {}) do
      if block.block_id == state.block_id and is_terminal_drawer(block) then
        return block
      end
    end
    state.block_id = nil
  end

  local drawer = nil
  local drawer_count = 0
  for _, block in ipairs(result.blocks or {}) do
    if is_terminal_drawer(block) then
      drawer = drawer or block
      drawer_count = drawer_count + 1
    end
  end

  if drawer_count > 1 then
    rex.log("warn", string.format(
      "Found %d terminal drawers in %s; using %s",
      drawer_count,
      session_id,
      drawer.block_id
    ))
  end
  if drawer ~= nil then
    state.block_id = drawer.block_id
  end
  return drawer
end

local function terminal_drawer_options()
  local options = {}
  local process = rex.block.call(terminal_creator, "process")
  local cwd = process_cwd(process)
  if cwd ~= nil then
    options.cwd = cwd
  end
  return options
end

local function create_terminal_drawer(session_id)
  local result, err = rex.session.new_block{
    session_id = session_id,
    flavor = terminal_shell,
    label = terminal_drawer_label,
    options = terminal_drawer_options(),
  }
  if result == nil then
    error(err or "unable to create the terminal drawer", 0)
  end
  terminal_drawer_state(session_id).block_id = result.block_id
  return {
    block_id = result.block_id,
    placement = "detached",
  }
end

local function create_floating_terminal_drawer(session_id, window_id, bounds)
  local result, err = rex.session.new_layer{
    session_id = session_id,
    window_id = window_id,
    bounds = bounds,
    focus = true,
    layout = rex.layout.block{
      flavor = terminal_shell,
      label = terminal_drawer_label,
      options = terminal_drawer_options(),
    },
  }
  if result == nil then
    error(err or "unable to create the floating terminal drawer", 0)
  end
  local block_id = (result.block_ids or {})[1]
  if block_id == nil then
    error("Rex created the terminal drawer without a pane ID", 0)
  end
  terminal_drawer_state(session_id).block_id = block_id
  return block_id, result.layer_id
end

local function move_terminal_drawer(session_id, block_id, anchor_block_id)
  local result, err = rex.session.move_block{
    session_id = session_id,
    block_id = block_id,
    anchor_block_id = anchor_block_id,
    direction = "horizontal",
    side = "after",
    ratio = 0.7,
  }
  if result == nil then
    error(err or "unable to place the terminal drawer", 0)
  end
end

local function float_terminal_drawer(session_id, block_id, anchor_block_id, bounds)
  local result, stage, err = move_and_float({
    session_id = session_id,
    block_id = block_id,
    anchor_block_id = anchor_block_id,
    bounds = bounds,
  })
  if result == nil then
    local fallback = stage == "move" and "unable to place the terminal drawer"
      or "unable to float the terminal drawer"
    error(err or fallback, 0)
  end
  return result.layer_id
end

local function floating_drawer_layer(view, drawer)
  if drawer == nil or drawer.placement ~= "placed" then
    return nil
  end

  local layer = find_block_layer(view, drawer.block_id)
  if layer ~= nil and layer.kind == "floating" then
    return layer
  end
  return nil
end

local function layer_contains_terminal_drawer(layer)
  for _, block in ipairs(layer and layer.blocks or {}) do
    if block.label == terminal_drawer_label then
      return true
    end
  end
  return false
end

local function remember_terminal_drawer_return_focus(session_id, view, drawer)
  local block_id = active_block_id(view)
  if block_id ~= nil and (drawer == nil or block_id ~= drawer.block_id) then
    terminal_drawer_return_focus_by_session[session_id] = block_id
  end
end

local function restore_terminal_drawer_focus(session_id, view, drawer_block_id)
  local block_id = terminal_drawer_return_focus_by_session[session_id]
  terminal_drawer_return_focus_by_session[session_id] = nil
  if block_id == drawer_block_id or find_block_layer(view, block_id) == nil then
    block_id = nil
  end

  if block_id == nil then
    local window = active_window(view)
    for _, layer in ipairs(window and window.layers or {}) do
      if layer.kind == "tiled" then
        for _, block in ipairs(layer.blocks or {}) do
          if block.block_id ~= drawer_block_id then
            block_id = block.block_id
            break
          end
        end
      end
      if block_id ~= nil then
        break
      end
    end
  end

  if block_id ~= nil then
    local result, err = rex.session.focus_block{
      session_id = session_id,
      block_id = block_id,
    }
    if result == nil then
      rex.log("warn", "Unable to restore focus after hiding the terminal drawer: " .. tostring(err))
    end
  end
end

local function focus_terminal_drawer(session_id, drawer, layer)
  if layer ~= nil then
    local raised, raise_err = rex.session.raise_layer{
      session_id = session_id,
      layer_id = layer.layer_id,
    }
    if raised == nil then
      error(raise_err or "unable to raise the terminal drawer", 0)
    end
  end

  local focused, focus_err = rex.session.focus_block{
    session_id = session_id,
    block_id = drawer.block_id,
  }
  if focused == nil then
    error(focus_err or "unable to focus the terminal drawer", 0)
  end
end

local function show_terminal_drawer(ctx, view, drawer, placement, bounds)
  local anchor_block_id = terminal_drawer_anchor_block_id(ctx.session_id, view)
  if drawer == nil and placement == "floating" then
    local block_id, layer_id = create_floating_terminal_drawer(
      ctx.session_id,
      view.active_window_id,
      bounds
    )
    update_terminal_drawer_state(ctx.session_id, placement, bounds, true)
    return {
      block_id = block_id,
      bounds = bounds,
      layer_id = layer_id,
      placement = placement,
      visible = true,
      window_id = view.active_window_id,
    }
  end

  if anchor_block_id == nil then
    error("the active tab has no tiled pane for the terminal drawer", 0)
  end
  if drawer == nil then
    drawer = create_terminal_drawer(ctx.session_id)
  end

  if placement == "docked" then
    move_terminal_drawer(ctx.session_id, drawer.block_id, anchor_block_id)
    focus_terminal_drawer(ctx.session_id, drawer, nil)
    update_terminal_drawer_state(ctx.session_id, placement, bounds, true)
    return {
      block_id = drawer.block_id,
      placement = placement,
      visible = true,
      window_id = view.active_window_id,
    }
  end

  local layer_id = float_terminal_drawer(
    ctx.session_id,
    drawer.block_id,
    anchor_block_id,
    bounds
  )
  focus_terminal_drawer(ctx.session_id, drawer, nil)
  update_terminal_drawer_state(ctx.session_id, placement, bounds, true)
  return {
    block_id = drawer.block_id,
    bounds = bounds,
    layer_id = layer_id,
    placement = placement,
    visible = true,
    window_id = view.active_window_id,
  }
end

local function hide_terminal_drawer(ctx, view, drawer, drawer_layer)
  local placement = drawer_layer and "floating" or "docked"
  local bounds = drawer_layer and drawer_layer.bounds or terminal_drawer_state(ctx.session_id).bounds
  local result, err = rex.session.detach_block{
    session_id = ctx.session_id,
    block_id = drawer.block_id,
  }
  if result == nil then
    error(err or "unable to hide the terminal drawer", 0)
  end
  update_terminal_drawer_state(ctx.session_id, placement, bounds, true)
  restore_terminal_drawer_focus(ctx.session_id, view, drawer.block_id)
  return {
    block_id = drawer.block_id,
    bounds = bounds,
    placement = placement,
    visible = false,
  }
end

rex.action{
  name = "toggle_terminal_drawer",
  title = "Toggle Terminal Drawer",
  description = "Focus, show, or fully hide the persistent terminal drawer for this session.",
  category = "Pane",
  keywords = "drawer floating persistent shell terminal summon hide focus",
  run = function(ctx)
    if ctx.session_id == nil then
      error("the terminal drawer needs an active Rex session", 0)
    end

    local view = view_or_error(ctx.session_id)
    local drawer = find_terminal_drawer(ctx.session_id)
    local drawer_layer = floating_drawer_layer(view, drawer)
    local state = terminal_drawer_state(ctx.session_id)
    if drawer_layer ~= nil then
      update_terminal_drawer_state(ctx.session_id, "floating", drawer_layer.bounds, false)
    elseif drawer ~= nil and drawer.placement == "placed" then
      state.placement = "docked"
    end

    if drawer ~= nil and drawer.window_id == view.active_window_id then
      if drawer_layer ~= nil and drawer_layer.state == "minimized" then
        remember_terminal_drawer_return_focus(ctx.session_id, view, drawer)
        local result, err = rex.session.detach_block{
          session_id = ctx.session_id,
          block_id = drawer.block_id,
        }
        if result == nil then
          error(err or "unable to migrate the minimized terminal drawer", 0)
        end
        update_terminal_drawer_state(ctx.session_id, "floating", drawer_layer.bounds, true)
        return show_terminal_drawer(ctx, view, drawer, "floating", drawer_layer.bounds)
      end

      if active_block_id(view) ~= drawer.block_id then
        remember_terminal_drawer_return_focus(ctx.session_id, view, drawer)
        focus_terminal_drawer(ctx.session_id, drawer, drawer_layer)
        return {
          block_id = drawer.block_id,
          bounds = drawer_layer and drawer_layer.bounds or state.bounds,
          layer_id = drawer_layer and drawer_layer.layer_id or nil,
          placement = drawer_layer and "floating" or "docked",
          visible = true,
        }
      end

      return hide_terminal_drawer(ctx, view, drawer, drawer_layer)
    end

    remember_terminal_drawer_return_focus(ctx.session_id, view, drawer)
    return show_terminal_drawer(ctx, view, drawer, state.placement, state.bounds)
  end,
}

rex.action{
  name = "toggle_terminal_drawer_dock",
  title = "Toggle Terminal Drawer Docking",
  description = "Switch the persistent terminal drawer between a floating overlay and a split beside its return pane.",
  category = "Pane",
  keywords = "drawer floating dock split overlay pin terminal",
  run = function(ctx)
    if ctx.session_id == nil then
      error("the terminal drawer needs an active Rex session", 0)
    end

    local view = view_or_error(ctx.session_id)
    local drawer = find_terminal_drawer(ctx.session_id)
    local drawer_layer = floating_drawer_layer(view, drawer)
    local state = terminal_drawer_state(ctx.session_id)
    if drawer_layer ~= nil then
      state.bounds = copy_bounds(drawer_layer.bounds)
    end
    remember_terminal_drawer_return_focus(ctx.session_id, view, drawer)

    if drawer ~= nil and drawer.window_id == view.active_window_id and drawer_layer == nil then
      local result, err = rex.session.float_block{
        session_id = ctx.session_id,
        block_id = drawer.block_id,
        bounds = state.bounds,
      }
      if result == nil then
        error(err or "unable to float the terminal drawer", 0)
      end
      focus_terminal_drawer(ctx.session_id, drawer, nil)
      update_terminal_drawer_state(ctx.session_id, "floating", state.bounds, true)
      return {
        block_id = drawer.block_id,
        bounds = state.bounds,
        layer_id = result.layer_id,
        placement = "floating",
        visible = true,
      }
    end

    if drawer ~= nil and drawer.window_id == view.active_window_id and drawer_layer ~= nil then
      local anchor_block_id = terminal_drawer_anchor_block_id(ctx.session_id, view)
      if anchor_block_id == nil then
        error("the active tab has no tiled pane for the terminal drawer", 0)
      end
      move_terminal_drawer(ctx.session_id, drawer.block_id, anchor_block_id)
      focus_terminal_drawer(ctx.session_id, drawer, nil)
      update_terminal_drawer_state(ctx.session_id, "docked", drawer_layer.bounds, true)
      return {
        block_id = drawer.block_id,
        placement = "docked",
        visible = true,
      }
    end

    return show_terminal_drawer(ctx, view, drawer, "docked", state.bounds)
  end,
}

rex.action{
  name = "toggle_terminal_drawer_park",
  title = "Park Terminal Drawer",
  description = "Minimize or restore the floating terminal drawer with Rex's native capsule.",
  category = "Pane",
  keywords = "drawer floating park minimize capsule restore terminal",
  run = function(ctx)
    if ctx.session_id == nil then
      error("the terminal drawer needs an active Rex session", 0)
    end

    local view = view_or_error(ctx.session_id)
    local drawer = find_terminal_drawer(ctx.session_id)
    local drawer_layer = floating_drawer_layer(view, drawer)
    local state = terminal_drawer_state(ctx.session_id)

    if drawer_layer == nil then
      remember_terminal_drawer_return_focus(ctx.session_id, view, drawer)
      local shown = show_terminal_drawer(ctx, view, drawer, "floating", state.bounds)
      shown.parked = false
      return shown
    end

    if drawer_layer.state == "minimized" then
      remember_terminal_drawer_return_focus(ctx.session_id, view, drawer)
      local restored, restore_err = rex.session.set_layer_state{
        session_id = ctx.session_id,
        layer_id = drawer_layer.layer_id,
        state = "normal",
        focus = true,
      }
      if restored == nil then
        error(restore_err or "unable to restore the parked terminal drawer", 0)
      end
      update_terminal_drawer_state(ctx.session_id, "floating", drawer_layer.bounds, true)
      return {
        block_id = drawer.block_id,
        bounds = drawer_layer.bounds,
        layer_id = drawer_layer.layer_id,
        parked = false,
        placement = "floating",
        visible = true,
      }
    end

    local parked, park_err = rex.session.set_layer_state{
      session_id = ctx.session_id,
      layer_id = drawer_layer.layer_id,
      state = "minimized",
    }
    if parked == nil then
      error(park_err or "unable to park the terminal drawer", 0)
    end
    update_terminal_drawer_state(ctx.session_id, "floating", drawer_layer.bounds, true)
    return {
      block_id = drawer.block_id,
      bounds = drawer_layer.bounds,
      layer_id = drawer_layer.layer_id,
      parked = true,
      placement = "floating",
      visible = false,
    }
  end,
}

rex.action{
  name = "set_terminal_drawer_preset",
  title = "Set Terminal Drawer Placement",
  description = "Show the terminal drawer with a named floating placement preset.",
  category = "Pane",
  keywords = "drawer floating preset right left center large geometry",
  args = { preset = "string" },
  run = function(ctx, args)
    if ctx.session_id == nil then
      error("the terminal drawer needs an active Rex session", 0)
    end
    local preset = terminal_drawer_presets[args.preset]
    if preset == nil then
      error("unknown terminal drawer preset: " .. tostring(args.preset), 0)
    end

    local bounds = copy_bounds(preset)
    local view = view_or_error(ctx.session_id)
    local drawer = find_terminal_drawer(ctx.session_id)
    local drawer_layer = floating_drawer_layer(view, drawer)
    remember_terminal_drawer_return_focus(ctx.session_id, view, drawer)

    if drawer ~= nil
      and drawer.window_id == view.active_window_id
      and drawer_layer ~= nil
      and drawer_layer.state ~= "minimized"
    then
      local result, err = rex.session.resize_layer{
        session_id = ctx.session_id,
        layer_id = drawer_layer.layer_id,
        bounds = bounds,
      }
      if result == nil then
        error(err or "unable to place the terminal drawer", 0)
      end
      focus_terminal_drawer(ctx.session_id, drawer, drawer_layer)
      update_terminal_drawer_state(ctx.session_id, "floating", bounds, true)
      return {
        block_id = drawer.block_id,
        bounds = bounds,
        layer_id = drawer_layer.layer_id,
        placement = "floating",
        preset = args.preset,
        visible = true,
      }
    end

    if drawer ~= nil
      and drawer.window_id == view.active_window_id
      and drawer_layer == nil
    then
      local result, err = rex.session.float_block{
        session_id = ctx.session_id,
        block_id = drawer.block_id,
        bounds = bounds,
      }
      if result == nil then
        error(err or "unable to float the terminal drawer", 0)
      end
      focus_terminal_drawer(ctx.session_id, drawer, nil)
      update_terminal_drawer_state(ctx.session_id, "floating", bounds, true)
      return {
        block_id = drawer.block_id,
        bounds = bounds,
        layer_id = result.layer_id,
        placement = "floating",
        preset = args.preset,
        visible = true,
      }
    end

    if drawer_layer ~= nil and drawer_layer.state == "minimized" then
      local result, err = rex.session.detach_block{
        session_id = ctx.session_id,
        block_id = drawer.block_id,
      }
      if result == nil then
        error(err or "unable to migrate the minimized terminal drawer", 0)
      end
    end
    local shown = show_terminal_drawer(ctx, view, drawer, "floating", bounds)
    shown.preset = args.preset
    return shown
  end,
}

local function preposition_terminal_drawer(session_id, view, target_window)
  local drawer = nil
  local drawer_layer = nil
  local drawer_window = nil
  for _, window in ipairs(view.windows or {}) do
    for _, layer in ipairs(window.layers or {}) do
      if layer.kind == "floating" and layer.state ~= "minimized" then
        for _, block in ipairs(layer.blocks or {}) do
          if block.label == terminal_drawer_label
            and block.creator_name == terminal_creator
            and block.flavor == terminal_shell
          then
            drawer = block
            drawer_layer = layer
            drawer_window = window
            break
          end
        end
      end
      if drawer ~= nil then
        break
      end
    end
    if drawer ~= nil then
      break
    end
  end

  if drawer == nil or drawer_window.window_id == target_window.window_id then
    return false
  end

  local anchor_block_id = tiled_block_id(target_window)
  if anchor_block_id == nil then
    error("the destination tab has no tiled pane for the terminal drawer", 0)
  end

  if drawer_window.focused_block_id == drawer.block_id then
    if drawer_window.window_id == view.active_window_id then
      local source_block_id = tiled_block_id(drawer_window)
      if source_block_id == nil then
        error("the source tab has no tiled pane to hold focus while moving the terminal drawer", 0)
      end
      local focused, focus_err = rex.session.focus_block{
        session_id = session_id,
        block_id = source_block_id,
      }
      if focused == nil then
        error(focus_err or "unable to move focus off the terminal drawer before switching tabs", 0)
      end
    else
      local detached, detach_err = rex.session.detach_block{
        session_id = session_id,
        block_id = drawer.block_id,
      }
      if detached == nil then
        error(detach_err or "unable to detach the inactive terminal drawer before switching tabs", 0)
      end
    end
  end

  local floated, stage, move_err = move_and_float({
    session_id = session_id,
    block_id = drawer.block_id,
    anchor_block_id = anchor_block_id,
    bounds = drawer_layer.bounds,
  })
  if floated == nil then
    local fallback = stage == "move" and "unable to pre-position the terminal drawer"
      or "unable to float the terminal drawer before switching tabs"
    error(move_err or fallback, 0)
  end

  return true
end

local function queue_tab_goto_with_terminal_drawer(ctx, index, current_view)
  local prepositioned = false
  if ctx.session_id ~= nil then
    local view = current_view
    if view == nil then
      local view_err
      view, view_err = rex.session.view{ session_id = ctx.session_id }
      if view == nil then
        rex.log("warn", "Unable to inspect the Rex session before switching tabs: " .. tostring(view_err))
      end
    end

    local target_window = view and (view.windows or {})[index] or nil
    if target_window ~= nil then
      local ok, result = pcall(preposition_terminal_drawer, ctx.session_id, view, target_window)
      if ok then
        prepositioned = result
      else
        rex.log("warn", "Unable to pre-position the terminal drawer: " .. tostring(result))
      end

    end
  end

  -- Use the client's native tab action so recent Rex builds can apply their
  -- no-blink tab-switch path after the drawer is ready in the destination.
  rex.client.queue("client.tab.goto", { index = index })
  return { index = index, prepositioned = prepositioned }
end

rex.action{
  name = "tab_goto_with_terminal_drawer",
  title = "Go to Tab with Terminal Drawer",
  description = "Move the visible terminal drawer before selecting a tab to avoid an intermediate layout flash.",
  category = "Tab",
  keywords = "tab window terminal drawer floating switch",
  args = { index = "integer" },
  run = function(ctx, args)
    return queue_tab_goto_with_terminal_drawer(ctx, args.index)
  end,
}

rex.action{
  name = "tab_offset_with_terminal_drawer",
  title = "Change Tab with Terminal Drawer",
  description = "Move the visible terminal drawer before selecting the next or previous tab.",
  category = "Tab",
  keywords = "tab window next previous terminal drawer floating switch",
  args = { offset = "integer" },
  run = function(ctx, args)
    if args.offset ~= -1 and args.offset ~= 1 then
      error("offset must be -1 or 1", 0)
    end

    local view, view_err = rex.session.view{ session_id = ctx.session_id }
    if view == nil then
      rex.log("warn", "Unable to inspect the Rex session before switching tabs: " .. tostring(view_err))
      rex.client.queue(args.offset == 1 and "client.tab.next" or "client.tab.previous")
      return { prepositioned = false }
    end

    local active_index = nil
    for index, window in ipairs(view.windows or {}) do
      if window.window_id == view.active_window_id then
        active_index = index
        break
      end
    end

    local window_count = #(view.windows or {})
    if active_index == nil or window_count == 0 then
      rex.client.queue(args.offset == 1 and "client.tab.next" or "client.tab.previous")
      return { prepositioned = false }
    end

    local target_index = ((active_index - 1 + args.offset) % window_count) + 1
    return queue_tab_goto_with_terminal_drawer(ctx, target_index, view)
  end,
}

  return {
    find_block_layer = find_block_layer,
    layer_contains_terminal_drawer = layer_contains_terminal_drawer,
    update_terminal_drawer_state = update_terminal_drawer_state,
    view_or_error = view_or_error,
  }
end
