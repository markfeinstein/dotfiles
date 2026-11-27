-- Run from the repository root with lua tests/rex/bindings.lua.
local bindings = {}

rex = {
  bind = function(key, action, args)
    bindings[key] = { action = action, args = args }
  end,
  mode = function() end,
}

dofile("rex/modules/bindings.lua")({
  prefix = function(key, action, args)
    rex.bind("ctrl+space>" .. key, action, args)
  end,
  password_picker_enabled = false,
})

assert(bindings["cmd+`"].action == "toggle_scratch_terminal")
assert(bindings["cmd+[Digit1]"].action == "client.tab.goto")
assert(bindings["ctrl+space>[Digit1]"].action == "client.tab.goto")
assert(bindings["ctrl+space>n"].action == "client.tab.next")
assert(bindings["ctrl+space>p"].action == "client.tab.previous")
assert(bindings["ctrl+space>`"] == nil)
print("bindings ok")
