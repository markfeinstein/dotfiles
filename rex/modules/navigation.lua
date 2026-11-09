return function(context)
  local yabai = context.yabai
  local terminal_creator = context.terminal_creator
  local terminal_shell = context.terminal_shell
  local terminal_drawer_label = context.terminal_drawer_label
  local terminal_drawer_return_focus_by_session = context.terminal_drawer_return_focus_by_session
  local terminal_owns_navigation = context.terminal_owns_navigation
  local active_block_id = context.active_block_id
  local active_window = context.active_window
  local prefix = context.prefix

local function layout_block_rect(node, block_id)
  if node == nil then
    return nil
  end
  if node.block_id == block_id then
    return node.rect
  end

  local split = node.split
  if split == nil then
    return nil
  end
  return layout_block_rect(split.before, block_id)
    or layout_block_rect(split.after, block_id)
end

local function active_window_block_rect(view, block_id)
  local window = active_window(view)
  for _, layer in ipairs(window and window.layers or {}) do
    local rect = layout_block_rect(layer.layout, block_id)
    if rect ~= nil then
      return rect
    end
  end
  return nil
end

local function directional_distance(source, target, direction)
  local source_x = source[1] + source[3] / 2
  local source_y = source[2] + source[4] / 2
  local target_x = target[1] + target[3] / 2
  local target_y = target[2] + target[4] / 2

  if direction == "left" and target_x < source_x then
    return source_x - target_x, math.abs(target_y - source_y)
  elseif direction == "right" and target_x > source_x then
    return target_x - source_x, math.abs(target_y - source_y)
  elseif direction == "up" and target_y < source_y then
    return source_y - target_y, math.abs(target_x - source_x)
  elseif direction == "down" and target_y > source_y then
    return target_y - source_y, math.abs(target_x - source_x)
  end

  return nil, nil
end

local function visible_block_in_direction(view, source_block_id, direction)
  local source_rect = active_window_block_rect(view, source_block_id)
  if source_rect == nil then
    return nil
  end

  local best_block = nil
  local best_primary = nil
  local best_secondary = nil
  local best_layer_index = nil
  local window = active_window(view)
  for layer_index, layer in ipairs(window and window.layers or {}) do
    if layer.state ~= "minimized" then
      for _, block in ipairs(layer.blocks or {}) do
        if block.block_id ~= source_block_id then
          local target_rect = layout_block_rect(layer.layout, block.block_id)
          if target_rect ~= nil then
            local primary, secondary = directional_distance(source_rect, target_rect, direction)
            if primary ~= nil
              and (best_primary == nil
                or primary < best_primary
                or (primary == best_primary and secondary < best_secondary)
                or (primary == best_primary and secondary == best_secondary and layer_index > best_layer_index))
            then
              best_block = block.block_id
              best_primary = primary
              best_secondary = secondary
              best_layer_index = layer_index
            end
          end
        end
      end
    end
  end

  return best_block
end

local function is_terminal_drawer_block(view, block_id)
  local window = active_window(view)
  for _, layer in ipairs(window and window.layers or {}) do
    for _, block in ipairs(layer.blocks or {}) do
      if block.block_id == block_id
        and block.label == terminal_drawer_label
        and block.creator_name == terminal_creator
        and block.flavor == terminal_shell
      then
        return true
      end
    end
  end
  return false
end

local function remember_drawer_navigation_entry(session_id, view, source_block_id, target_block_id)
  if session_id ~= nil
    and source_block_id ~= nil
    and target_block_id ~= nil
    and source_block_id ~= target_block_id
    and is_terminal_drawer_block(view, target_block_id)
  then
    terminal_drawer_return_focus_by_session[session_id] = source_block_id
  end
end

local native_direction = {
  down = "south",
  left = "west",
  right = "east",
  up = "north",
}

local ctrl_key_data = {
  h = string.char(8),
  j = string.char(10),
  k = string.char(11),
  l = string.char(12),
}

local function forward_terminal_ctrl_key(key)
  local written, write_err = rex.block.call(terminal_creator, "write", {
    data = ctrl_key_data[key],
  })
  if written == nil then
    rex.log("warn", "Unable to forward Ctrl-" .. key:upper() .. ": " .. tostring(write_err))
  end
  return true
end

local function navigate_rex_or_native(direction, key)
  return function(ctx)
    local terminal_owns_key, process_err = terminal_owns_navigation(ctx)
    if terminal_owns_key == nil then
      rex.log("warn", "Ctrl navigation process check failed: " .. tostring(process_err))
      return false
    end
    if terminal_owns_key then
      -- Named Rex actions always consume their key; returning false is only an
      -- action result, not terminal passthrough. Write the control byte
      -- explicitly so Neovim and fzf receive their native mapping.
      return forward_terminal_ctrl_key(key)
    end

    local session_id = ctx and ctx.session_id or nil
    local before, view_err = rex.session.view{ session_id = session_id }
    if before == nil then
      rex.log("warn", "Ctrl navigation session query failed: " .. tostring(view_err))
      return false
    end

    local before_block = active_block_id(before)
    local focused, focus_err = rex.session.focus_direction{
      session_id = session_id,
      direction = direction,
      wrap = false,
    }
    if focused == nil then
      rex.log("warn", "Rex pane navigation failed: " .. tostring(focus_err))
    end

    local after, after_err = rex.session.view{ session_id = session_id }
    if after == nil then
      -- The focus call may already have moved to another Rex pane. Do not
      -- guess and double-move into a native window when verification fails.
      rex.log("warn", "Rex post-navigation query failed: " .. tostring(after_err))
      return true
    end

    local after_block = active_block_id(after)
    if before_block ~= nil and after_block ~= nil and after_block ~= before_block then
      remember_drawer_navigation_entry(session_id, after, before_block, after_block)
      return true
    end

    -- Some current Rex builds still omit floating layers when resolving a
    -- direction. Only after the native method leaves focus unchanged, locate
    -- the nearest visible block geometrically across tiled and floating layers.
    if before_block ~= nil then
      local target_block = visible_block_in_direction(before, before_block, direction)
      if target_block ~= nil then
        local fallback, fallback_err = rex.session.focus_block{
          session_id = session_id,
          block_id = target_block,
        }
        if fallback == nil then
          rex.log("warn", "Unable to focus the fallback Rex pane: " .. tostring(fallback_err))
        else
          remember_drawer_navigation_entry(session_id, before, before_block, target_block)
        end
        return true
      end

      -- No Rex pane exists in this direction. Preserve the existing
      -- outer-edge fallback to the native window manager.
      rex.exec({ yabai, "-m", "window", "--focus-robust", native_direction[direction] }, {
        timeout = 2,
        stdout = false,
        stderr = false,
      })
    end

    return true
  end
end

-- macOS reports these legacy control chords without a dependable logical
-- character, so match Rex's physical key codes instead. Bind named actions
-- rather than Lua callbacks because current Rex clients do not dispatch
-- callback bindings while a floating pane has focus.
for _, item in ipairs({
  { key = "h", physical = "[KeyH]", direction = "left" },
  { key = "j", physical = "[KeyJ]", direction = "down" },
  { key = "k", physical = "[KeyK]", direction = "up" },
  { key = "l", physical = "[KeyL]", direction = "right" },
}) do
  local action_name = "navigate_rex_or_native_" .. item.direction
  rex.action{
    name = action_name,
    title = "Navigate " .. item.direction,
    description = "Move focus to a Rex pane or the adjacent native window.",
    category = "Pane",
    keywords = "focus navigation pane window " .. item.direction,
    run = navigate_rex_or_native(item.direction, item.key),
  }
  rex.bind("ctrl+" .. item.physical, action_name)
  prefix("alt+shift+" .. item.key, "pane.move", { direction = item.direction })
end

end
