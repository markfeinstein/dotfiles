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

function M.process_cwd(process)
  local cwd = process and process.foreground and process.foreground.cwd or nil
  if (cwd == nil or cwd == "") and process and process.child ~= nil then
    cwd = process.child.cwd
  end
  return cwd ~= "" and cwd or nil
end

return M
