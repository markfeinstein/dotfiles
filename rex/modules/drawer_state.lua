return function(context)
  local presets = context.presets
  local default_preset = context.default_preset
  local directory = context.directory
  local path = context.path
  local header = context.header
  local version = context.version
  local copy_bounds = context.copy_bounds
  local valid_bounds = context.valid_bounds
  local write_atomic = context.write_atomic

  local state_by_session = {}
  local return_focus_by_session = {}
  local directory_ready = false

  local function state(session_id)
    local value = state_by_session[session_id]
    if value == nil then
      value = {
        block_id = nil,
        bounds = copy_bounds(presets[default_preset]),
        placement = "floating",
      }
      state_by_session[session_id] = value
    end
    return value
  end

  local function load()
    local file = io.open(path, "r")
    if file == nil then
      return
    end

    for line in file:lines() do
      local saved_version = line:match("^# rex%-terminal%-drawer%-state%-v(%d+)$")
      if saved_version ~= nil then
        if tonumber(saved_version) > version then
          rex.log("warn", "Ignoring terminal drawer state from newer format version " .. saved_version)
          file:close()
          directory_ready = true
          return
        end
      elseif line:sub(1, 1) ~= "#" then
        local session_id, placement, x, y, width, height, block_id = line:match(
          "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$"
        )
        if session_id == nil then
          session_id, placement, x, y, width, height = line:match(
            "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$"
          )
        end
        local bounds = { tonumber(x), tonumber(y), tonumber(width), tonumber(height) }
        if session_id ~= nil
          and (placement == "floating" or placement == "docked")
          and valid_bounds(bounds)
        then
          state_by_session[session_id] = {
            block_id = block_id ~= nil and block_id ~= "-" and block_id or nil,
            bounds = bounds,
            placement = placement,
          }
        end
      end
    end
    file:close()
    directory_ready = true
  end

  local function prune()
    local result, err = rex.call("session.list")
    if result == nil then
      rex.log("warn", "Unable to prune terminal drawer state: " .. tostring(err))
      return
    end

    local live_session_ids = {}
    for _, session in ipairs(result.sessions or {}) do
      live_session_ids[session.session_id] = true
    end
    for session_id in pairs(state_by_session) do
      if not live_session_ids[session_id] then
        state_by_session[session_id] = nil
        return_focus_by_session[session_id] = nil
      end
    end
  end

  local function save()
    prune()
    if not directory_ready then
      local result, err = rex.exec({ "mkdir", "-p", directory }, {
        timeout = 2,
        stdout = false,
        stderr = false,
      })
      if result == nil or not result.ok then
        rex.log("warn", "Unable to create the terminal drawer state directory: " .. tostring(err))
        return
      end
      directory_ready = true
    end

    local written, write_err = write_atomic(path, function(file)
      file:write(header .. "\n")
      local session_ids = {}
      for session_id in pairs(state_by_session) do
        table.insert(session_ids, session_id)
      end
      table.sort(session_ids)
      for _, session_id in ipairs(session_ids) do
        local value = state_by_session[session_id]
        local bounds = value.bounds
        file:write(string.format(
          "%s\t%s\t%.17g\t%.17g\t%.17g\t%.17g\t%s\n",
          session_id,
          value.placement,
          bounds[1],
          bounds[2],
          bounds[3],
          bounds[4],
          value.block_id or "-"
        ))
      end
    end)
    if written == nil then
      rex.log("warn", "Unable to write terminal drawer state: " .. tostring(write_err))
    end
  end

  local function update(session_id, placement, bounds, persist)
    local value = state(session_id)
    if placement ~= nil then
      value.placement = placement
    end
    if valid_bounds(bounds) then
      value.bounds = copy_bounds(bounds)
    end
    if persist then
      save()
    end
    return value
  end

  load()

  return {
    by_session = state_by_session,
    return_focus_by_session = return_focus_by_session,
    state = state,
    update = update,
  }
end
