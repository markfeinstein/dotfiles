-- Run from the repository root with lua tests/rex/docs_picker.lua.
local actions, picked, why, opened = {}, nil, nil, nil
rex = {
  action = function(action) actions[action.name] = action.run end,
  ui = { pick = function(prompt)
    assert(#prompt.items == 3 and not prompt.multiple)
    return picked, why
  end },
  client = { queue = function(action, args)
    assert(action == "client.url.open")
    opened = args.url
  end },
}
dofile("rex/modules/pickers.lua")({})
local run = assert(actions.rex_docs_picker)
why = "cancelled"
assert(run() == false and not opened)
why = "no_client"
assert(not pcall(run) and not opened)
picked = "unlisted"
assert(not pcall(run) and not opened)
picked = "reference/api"
assert(run() and opened == "https://www.superlogical.com/rex/docs/reference/api")
