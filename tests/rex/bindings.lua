-- Run from the repository root with lua tests/rex/bindings.lua.
local bindings = {}

rex = {
  bind = function(key, action, args)
    bindings[key] = { action = action, args = args }
  end,
  mode = function() end,
}

dofile("rex/modules/bindings.lua")({
  prefix = function() end,
  password_picker_enabled = false,
  terminal_drawer_default_preset = "right",
})

assert(bindings["cmd+`"].action == "pane.new_floating")
print("bindings ok")
