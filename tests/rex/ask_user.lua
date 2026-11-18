-- Run from the repository root with lua tests/rex/ask_user.lua.
local actions, last = {}, nil
local reply = {}
rex = {
  action = function(action) actions[action.name] = action.run end,
  ui = {
    input = function(prompt) last = { kind = "input", prompt = prompt }; return reply[1], reply[2], reply[3] end,
    pick = function(prompt) last = { kind = "pick", prompt = prompt }; return reply[1], reply[2], reply[3] end,
  },
}
dofile("rex/modules/prompts.lua")({ terminal_shell = "com.superlogical.terminal.shell" })
local ask = assert(actions.ask_user)

-- Without options it asks for text.
reply = { "feature/x" }
local result = ask({}, { question = "Branch?" })
assert(last.kind == "input" and last.prompt.title == "Branch?")
assert(result.status == "answered" and result.answer == "feature/x")

-- With options it shows a list and returns the chosen id.
reply = { "b" }
result = ask({}, { question = "Pick", options = { "a", "b" } })
assert(last.kind == "pick" and #last.prompt.items == 2 and last.prompt.allow_other == false)
assert(result.answer == "b")

-- Typed text from allow_other comes back flagged.
reply = { { text = "c" } }
result = ask({}, { question = "Pick", options = { "a" }, allow_other = true })
assert(result.answer == "c" and result.other == true)

-- A missing answer is a result, not an error.
reply = { nil, "cancelled" }
result = ask({}, { question = "Pick", options = { "a" } })
assert(result.status == "cancelled" and result.answer == nil)
reply = { nil, "failed", "boom" }
result = ask({}, { question = "Text" })
assert(result.status == "failed" and result.detail == "boom")

-- Bad arguments are errors.
assert(not pcall(ask, {}, { question = "" }))
assert(not pcall(ask, {}, { question = "Q", timeout = 0 }))
print("ask_user ok")
