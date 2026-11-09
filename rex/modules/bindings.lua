return function(context)
  local prefix = context.prefix
  local password_picker_enabled = context.password_picker_enabled
  local terminal_drawer_default_preset = context.terminal_drawer_default_preset

-- Direct macOS overrides extend the built-in terminal workflow.
rex.bind("cmd+n", "session.new")
rex.bind("cmd+s", "session.switch")
rex.bind("cmd+k", "session.switch")
rex.bind("cmd+l", "open_url_picker")
rex.bind("cmd+shift+l", "session.next")
rex.bind("cmd+b", "client.sidebar.toggle")
rex.bind("cmd+m", "model_picker")
rex.bind("cmd+`", "toggle_terminal_drawer")
-- yabai maps Cmd-H to this private direct chord so macOS Hide cannot win
-- and no prefix timing is involved.
rex.bind("ctrl+alt+cmd+[KeyH]", "client.sidebar.toggle")
rex.bind("cmd+r", "client.mode.enter", { name = "resize" })
rex.bind("cmd+shift+r", "client.config.reload")
rex.bind("cmd+g", "open_lazygit")
rex.bind("cmd+o", "file_picker")
rex.bind("cmd+[Minus]", "pane.split", { direction = "down" })
rex.bind("cmd+shift+[Backslash]", "pane.split", { direction = "right" })

for index = 1, 9 do
  rex.bind("cmd+[Digit" .. index .. "]", "tab_goto_with_terminal_drawer", { index = index })
  prefix("[Digit" .. index .. "]", "tab_goto_with_terminal_drawer", { index = index })
end

-- Ctrl-Space provides a consistent prefix for Rex's built-in workflow actions.
prefix("ctrl+space", "pane.send_key", { key = "ctrl+space" })
prefix("c", "client.tab.new")
prefix("x", "pane.close")
prefix("shift+x", "client.tab.close")
prefix("s", "pane.split", { direction = "down" })
prefix("v", "pane.split", { direction = "right" })
prefix("z", "pane.zoom")
prefix("=", "pane.balance")
prefix("r", "client.mode.enter", { name = "resize" })
prefix("shift+r", "client.config.reload")
prefix("n", "tab_offset_with_terminal_drawer", { offset = 1 })
prefix("p", "tab_offset_with_terminal_drawer", { offset = -1 })
if password_picker_enabled then
  prefix("shift+p", "password_picker")
end
prefix("shift+n", "session.new")
prefix("shift+s", "session.switch")
prefix("l", "session.previous")
prefix("shift+l", "session.next")
prefix("b", "client.sidebar.toggle")
prefix("alt+h", "client.sidebar.toggle")
prefix("shift+b", "client.sidebar.activity.toggle")
prefix("[BracketLeft]", "swap_pane", { offset = -1 })
prefix("[BracketRight]", "swap_pane", { offset = 1 })
prefix("o", "transpose_split")
prefix("m", "pane.move_to_tab")
prefix("shift+m", "pane.move_to_new_tab")
prefix("shift+left", "client.tab.move", { direction = "backward" })
prefix("shift+right", "client.tab.move", { direction = "forward" })
prefix("f", "client.find.open")
prefix("g", "open_github_dashboard")
prefix("e", "edit_scrollback")
prefix("alt+n", "client.find.next")
prefix("alt+p", "client.find.previous")
prefix("up", "client.prompt.previous")
prefix("down", "client.prompt.next")
prefix("shift+=", "client.font.increase")
prefix("-", "client.font.decrease")
prefix("0", "client.font.reset")
prefix("t", "client.theme.change")
prefix("shift+t", "client.appearance.switch_mode", { mode = "toggle" })
prefix("alt+t", "client.tab_style.toggle")
prefix("`", "toggle_terminal_drawer_dock")
prefix("shift+`", "toggle_terminal_drawer_park")

-- Resize mode stays active until Enter, Escape, or Q. Floating panes move
-- with unshifted directions and resize with shifted directions; tiled panes
-- retain their existing split-resize behavior.
rex.mode("resize", { exclusive = true })
for _, item in ipairs({
  { key = "h", direction = "left", amount = 5, operation = "move" },
  { key = "j", direction = "down", amount = 2, operation = "move" },
  { key = "k", direction = "up", amount = 2, operation = "move" },
  { key = "l", direction = "right", amount = 5, operation = "move" },
  { key = "left", direction = "left", amount = 5, operation = "move" },
  { key = "down", direction = "down", amount = 2, operation = "move" },
  { key = "up", direction = "up", amount = 2, operation = "move" },
  { key = "right", direction = "right", amount = 5, operation = "move" },
  { key = "shift+h", direction = "left", amount = 15, operation = "resize" },
  { key = "shift+j", direction = "down", amount = 10, operation = "resize" },
  { key = "shift+k", direction = "up", amount = 10, operation = "resize" },
  { key = "shift+l", direction = "right", amount = 15, operation = "resize" },
  { key = "shift+left", direction = "left", amount = 15, operation = "resize" },
  { key = "shift+down", direction = "down", amount = 10, operation = "resize" },
  { key = "shift+up", direction = "up", amount = 10, operation = "resize" },
  { key = "shift+right", direction = "right", amount = 15, operation = "resize" },
}) do
  rex.bind("resize/" .. item.key, "adjust_pane_geometry", {
    amount = item.amount,
    direction = item.direction,
    operation = item.operation,
  })
end
for key, preset in pairs({
  ["0"] = terminal_drawer_default_preset,
  ["1"] = "right",
  ["2"] = "left",
  ["3"] = "center",
  ["4"] = "large",
}) do
  rex.bind("resize/" .. key, "set_terminal_drawer_preset", { preset = preset })
end
rex.bind("resize/=", "pane.balance")
rex.bind("resize/enter", "client.mode.exit")
rex.bind("resize/q", "client.mode.exit")

end
