return function(context)
  local copy_bounds = context.copy_bounds
  local find_block_layer = context.find_block_layer
  local layer_contains_terminal_drawer = context.layer_contains_terminal_drawer
  local update_terminal_drawer_state = context.update_terminal_drawer_state
  local view_or_error = context.view_or_error

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

rex.action{
  name = "adjust_pane_geometry",
  title = "Adjust Pane Geometry",
  description = "Move or resize a floating pane, falling back to split resizing for tiled panes.",
  category = "Pane",
  keywords = "floating move resize geometry pane split",
  args = {
    amount = "integer",
    direction = "string",
    operation = "string",
  },
  repeats = true,
  run = function(ctx, args)
    if ctx.block_id == nil then
      error("no focused pane", 0)
    end
    if args.direction ~= "left"
      and args.direction ~= "right"
      and args.direction ~= "up"
      and args.direction ~= "down"
    then
      error("direction must be left, right, up, or down", 0)
    end
    if args.operation ~= "move" and args.operation ~= "resize" then
      error("operation must be move or resize", 0)
    end

    local layer = find_block_layer(view_or_error(ctx.session_id), ctx.block_id)
    if layer == nil then
      error("the focused pane is not in a visible layer", 0)
    end
    if layer.kind ~= "floating" then
      rex.client.queue("pane.resize", {
        amount = args.amount,
        direction = args.direction,
      })
      return { floating = false }
    end

    local bounds = copy_bounds(layer.bounds)
    local amount = (args.amount or 5) / 100
    if args.operation == "move" then
      if args.direction == "left" then
        bounds[1] = clamp(bounds[1] - amount, 0, 1 - bounds[3])
      elseif args.direction == "right" then
        bounds[1] = clamp(bounds[1] + amount, 0, 1 - bounds[3])
      elseif args.direction == "up" then
        bounds[2] = clamp(bounds[2] - amount, 0, 1 - bounds[4])
      else
        bounds[2] = clamp(bounds[2] + amount, 0, 1 - bounds[4])
      end
    elseif args.direction == "left" then
      bounds[3] = clamp(bounds[3] - amount, 0.20, 1 - bounds[1])
    elseif args.direction == "right" then
      bounds[3] = clamp(bounds[3] + amount, 0.20, 1 - bounds[1])
    elseif args.direction == "up" then
      bounds[4] = clamp(bounds[4] - amount, 0.20, 1 - bounds[2])
    else
      bounds[4] = clamp(bounds[4] + amount, 0.20, 1 - bounds[2])
    end

    local result, err = rex.session.resize_layer{
      session_id = ctx.session_id,
      layer_id = layer.layer_id,
      bounds = bounds,
    }
    if result == nil then
      error(err or "unable to adjust the floating pane", 0)
    end
    if layer_contains_terminal_drawer(layer) then
      update_terminal_drawer_state(ctx.session_id, "floating", bounds, true)
    end
    return {
      bounds = bounds,
      floating = true,
      operation = args.operation,
    }
  end,
}

rex.action{
  name = "swap_pane",
  title = "Swap Pane",
  description = "Swap the focused pane with the previous or next pane in layout order.",
  category = "Pane",
  keywords = "exchange rotate previous next",
  args = { offset = "integer" },
  repeats = true,
  run = function(ctx, args)
    if ctx.block_id == nil then
      error("no focused pane", 0)
    end
    if args.offset ~= -1 and args.offset ~= 1 then
      error("offset must be -1 or 1", 0)
    end

    local layer, index = find_block_layer(view_or_error(), ctx.block_id)
    if layer == nil then
      error("the focused pane is not in a visible layer", 0)
    end

    local blocks = layer.blocks or {}
    if #blocks < 2 then
      error("the focused layer has no other pane to swap", 0)
    end

    local other_index = index + args.offset
    if other_index < 1 then
      other_index = #blocks
    elseif other_index > #blocks then
      other_index = 1
    end

    local result, err = rex.session.swap_blocks{
      block_id = ctx.block_id,
      other_block_id = blocks[other_index].block_id,
    }
    if result == nil then
      error(err, 0)
    end
    return { other_block_id = blocks[other_index].block_id }
  end,
}

local function find_parent_split(node, block_id)
  local split = node and node.split or nil
  if split == nil then
    return nil, nil
  end

  for _, side in ipairs({ "before", "after" }) do
    local child = split[side]
    if child ~= nil and child.block_id == block_id then
      return split, side
    end
  end

  for _, side in ipairs({ "before", "after" }) do
    local found, found_side = find_parent_split(split[side], block_id)
    if found ~= nil then
      return found, found_side
    end
  end
  return nil, nil
end

rex.action{
  name = "transpose_split",
  title = "Transpose Split",
  description = "Switch the focused pane's split between stacked and side-by-side.",
  category = "Pane",
  keywords = "rotate orientation horizontal vertical",
  run = function(ctx)
    if ctx.block_id == nil then
      error("no focused pane", 0)
    end

    local view = view_or_error()
    for _, window in ipairs(view.windows or {}) do
      for _, layer in ipairs(window.layers or {}) do
        local split, side = find_parent_split(layer.layout, ctx.block_id)
        if split ~= nil then
          local sibling = split[side == "before" and "after" or "before"]
          if sibling.block_id == nil then
            error("the neighbouring pane is a group; transpose from one of its panes", 0)
          end

          local direction = split.direction == "horizontal" and "vertical" or "horizontal"
          local result, err = rex.session.move_block{
            block_id = ctx.block_id,
            anchor_block_id = sibling.block_id,
            direction = direction,
            side = side,
            ratio = split.ratio,
          }
          if result == nil then
            error(err, 0)
          end
          return { direction = direction }
        end
      end
    end
    error("the focused pane has no split to transpose", 0)
  end,
}

end
