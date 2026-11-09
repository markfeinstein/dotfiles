local M = {}

function M.active_window(view)
  if view == nil or view.windows == nil then
    return nil
  end

  for _, window in ipairs(view.windows) do
    if window.window_id == view.active_window_id then
      return window
    end
  end
  return nil
end

function M.tiled_block_id(window)
  if window == nil then
    return nil
  end

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

function M.process_cwd(process)
  local cwd = process and process.foreground and process.foreground.cwd or nil
  if (cwd == nil or cwd == "") and process and process.child ~= nil then
    cwd = process.child.cwd
  end
  return cwd ~= "" and cwd or nil
end

function M.write_atomic(path, writer)
  local temporary_path = path .. ".tmp"
  local file, open_err = io.open(temporary_path, "w")
  if file == nil then
    return nil, open_err
  end

  local wrote, write_err = pcall(writer, file)
  if not wrote then
    file:close()
    os.remove(temporary_path)
    return nil, write_err
  end

  local closed, close_err = file:close()
  if closed == nil then
    os.remove(temporary_path)
    return nil, close_err
  end

  local renamed, rename_err = os.rename(temporary_path, path)
  if renamed == nil then
    os.remove(temporary_path)
    return nil, rename_err
  end
  return true
end

function M.move_and_float(opts)
  local moved, move_err = rex.session.move_block{
    session_id = opts.session_id,
    block_id = opts.block_id,
    anchor_block_id = opts.anchor_block_id,
    direction = opts.direction or "horizontal",
    side = opts.side or "after",
    ratio = opts.ratio or 0.7,
  }
  if moved == nil then
    return nil, "move", move_err
  end

  local floated, float_err = rex.session.float_block{
    session_id = opts.session_id,
    block_id = opts.block_id,
    bounds = opts.bounds,
  }
  if floated ~= nil then
    return floated
  end

  local _, detach_err = rex.session.detach_block{
    session_id = opts.session_id,
    block_id = opts.block_id,
  }
  if detach_err ~= nil then
    float_err = tostring(float_err) .. "; cleanup failed: " .. tostring(detach_err)
  end
  return nil, "float", float_err
end

return M
