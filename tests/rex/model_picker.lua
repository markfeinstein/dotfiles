-- Run from the repository root with lua tests/rex/model_picker.lua.
local actions, sent, picked = {}, {}, nil
local foreground = "pi"
local list_reply = "ok;protocol=2;scope=all;idle=1;refresh=current\t\theader\n"
  .. '["anthropic","opus"]\t{"action":"select","provider":"anthropic","modelId":"opus"}\t'
  .. "\27[92m\226\156\147\27[0m \27[93m\226\152\133\27[0m Opus 5.5 1M          \27[2m Anthropic \27[0m  1M      128K   \27[96m      $5\27[0m  \27[95m      $25\27[0m  x  y  \27[8m   anthropic opus hidden\27[0m\n"
  .. '["openai","gpt-4"]\t{"action":"select","provider":"openai","modelId":"gpt-4"}\t'
  .. "    GPT 4                \27[2m OpenAI    \27[0m  \27[91m!8.19K\27[0m  8.19K  \27[96m     $30\27[0m  \27[95m      $60\27[0m  —  —  \27[8m  openai gpt-4\27[0m\n"
local decode = {
  ['["anthropic","opus"]'] = { "anthropic", "opus" },
  ['["openai","gpt-4"]'] = { "openai", "gpt-4" },
}
rex = {
  action = function(action) actions[action.name] = action.run end,
  exec = function(argv, opts)
    assert(argv[1] == "/usr/bin/nc" and argv[2] == "-U" and argv[3]:match("/pi/model%-picker/abc%.sock$"))
    table.insert(sent, opts.stdin)
    if opts.stdin:find('"list"', 1, true) then return { ok = true, stdout = list_reply } end
    return { ok = true, stdout = "ok\tanthropic/opus\n" }
  end,
  json = { decode = function(text) return decode[text] end },
  ui = { pick = function(prompt) picked = prompt; return prompt.items[1].id end },
  block = { call = function(_, method, args)
    assert(method == "process" and args.block_id == "block:abc")
    return { foreground = { name = foreground } }
  end },
}
dofile("rex/modules/prompts.lua")({
  terminal_creator = "t", terminal_shell = "s", process_cwd = function() end, git_project = "g",
  normalized_process_name = function(process) return process and process.name end,
})
local run = assert(actions.model_picker)

assert(run({ block_id = "block:abc" }) == true)
local items = picked.items
assert(#items == 2)
assert(items[1].title == "Opus 5.5 1M" and items[1].icon == "star")
assert(items[1].subtitle == "anthropic · 1M context · 128K output · thinking, images")
assert(picked.title == "Pi model")
assert(items[1].detail == "$5 / $25")
assert(items[2].title == "GPT 4" and items[2].icon == nil)
assert(items[2].subtitle == "openai · 8.19K (too small) context · 8.19K output")
-- The chosen row's own select request goes back to Pi.
assert(sent[2] == '{"action":"select","provider":"anthropic","modelId":"opus"}\n')

-- Outside a Pi pane it does nothing, like the floating picker.
foreground = "nu"
local before = #sent
assert(run({ block_id = "block:abc" }) == false and #sent == before)
foreground = "pi"

-- A busy Pi is named in the title.
list_reply = list_reply:gsub("idle=1", "idle=0")
run({ block_id = "block:abc" })
assert(picked.title:find("busy", 1, true))

-- Pi's errors surface as action errors.
rex.exec = function() return { ok = true, stdout = "error\tPi is busy\n" } end
local ok, err = pcall(run, { block_id = "block:abc" })
assert(not ok and err:find("Pi is busy", 1, true))
print("model picker ok")
