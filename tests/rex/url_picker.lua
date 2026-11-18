-- Run from the repository root with lua tests/rex/url_picker.lua.
local actions, picked, execs = {}, nil, {}
local pick_reply = {}
local html, blob_calls = "", 0

rex = {
  action = function(action) actions[action.name] = action.run end,
  ui = { pick = function(prompt) picked = prompt; return pick_reply[1], pick_reply[2] end },
  exec = function(argv, opts) table.insert(execs, { argv = argv, opts = opts }); return { ok = true, code = 0 } end,
  block = { call = function(creator, method, args)
    assert(creator == "com.superlogical.terminal" and args.block_id == "block:b")
    if method == "format" then
      assert(args.format == "html" and args.unwrap and args.trim)
      if #html <= args.max_bytes then return { content = html } end
      return { content = html:sub(1, args.max_bytes), id = 7, total = #html }
    end
    assert(method == "blob_read" and args.id == 7)
    blob_calls = blob_calls + 1
    local data = html:sub(args.offset + 1, args.offset + math.min(args.max_bytes, 5000))
    return { data = data, eof = args.offset + #data >= #html }
  end },
}
local url = dofile("rex/modules/url_picker.lua")({ terminal_creator = "com.superlogical.terminal", line_limit = 5 })
local run = assert(actions.open_url_picker)

-- rex-picker's own case: hyperlinks, visible URLs, balanced punctuation,
-- duplicates, newest first.
local found = url.extract(table.concat({
  '<div><a href="https://docs.example.com/guide_(one)">Rex documentation</a></div>\n',
  "<div>Visible https://example.com/wiki/Function_(mathematics)).</div>\n",
  "<div>Duplicate https://example.com/wiki/Function_(mathematics)</div>\n",
  "<div>Newest https://second.example/path?q=1;</div>\n",
}))
assert(#found == 3)
assert(found[1].url == "https://second.example/path?q=1" and found[1].label == nil)
assert(found[2].url == "https://example.com/wiki/Function_(mathematics)")
assert(found[3].url == "https://docs.example.com/guide_(one)" and found[3].label == "Rex documentation")

-- Entities decode, non-HTTP links and hosts without names are skipped, and a
-- link whose text is its own URL gets no label.
found = url.extract('<a href="https://a.example/x?b=1&amp;c=2">https://a.example/x?b=1&amp;c=2</a>'
  .. ' <a href="mailto:me@example.com">mail</a> http:// and ftp://x.example done')
assert(#found == 1 and found[1].url == "https://a.example/x?b=1&c=2" and found[1].label == nil)

-- Other devices see host and path only.
assert(url.display("https://user:pw@github.com/org/repo/pull/6083?token=abc#frag") == "github.com/org/repo/pull/6083?…")
assert(url.display("https://chat.example.com/hooks/T01AB2CD3/B04EF5GH6/Xy9Zq8Wv7Ut6Sr5Qp4On3Ml2") == "chat.example.com/hooks/T01AB2CD3/B04EF5GH6/…")
assert(url.display("https://github.com/o/r/tree/user-mfeinstein-SWE-2028-eks-gcs-acceptance-job")
  == "github.com/o/r/tree/user-mfeinstein-SWE-2028-eks-gcs-acceptance-job")
assert(url.display("https://example.com") == "example.com/")
assert(url.display("https://x.example/files/3f2a9c1e-7b4d-4e8a-9c2b-1d5e6f7a8b9c") == "x.example/files/…")

-- Choosing opens the full URL, while the prompt only carried row numbers and
-- redacted text.
html = '<div>see https://a.example/one?secret=s3cr3t</div>\n<div><a href="https://b.example/two">Docs</a></div>\n'
pick_reply = { "2" }
assert(run({ block_id = "block:b" }, {}) == true)
for _, item in ipairs(picked.items) do
  for _, field in ipairs({ "id", "title", "subtitle" }) do
    assert(not tostring(item[field] or ""):find("s3cr3t", 1, true), "a secret reached the prompt")
  end
end
assert(picked.items[1].id == "1" and picked.items[2].id == "2")
assert(picked.items[1].title == "Docs" and picked.items[1].subtitle == "b.example/two")
assert(picked.items[2].title == "a.example/one?…")
assert(execs[#execs].argv[1] == "/usr/bin/open" and execs[#execs].argv[2] == "https://a.example/one?secret=s3cr3t")

-- Copy sends the URL to the clipboard on stdin; background keeps the browser behind.
pick_reply = { "1" }
run({ block_id = "block:b" }, { mode = "copy" })
assert(execs[#execs].argv[1] == "/usr/bin/pbcopy" and execs[#execs].opts.stdin == "https://b.example/two")
run({ block_id = "block:b" }, { mode = "background" })
assert(execs[#execs].argv[2] == "-g" and execs[#execs].argv[3] == "https://b.example/two")
assert(picked.title == "Open URL in the background")
assert(not pcall(run, { block_id = "block:b" }, { mode = "print" }))

-- Cancelling is quiet; an empty pane is an error.
pick_reply = { nil, "cancelled" }
assert(run({ block_id = "block:b" }, {}) == false)
html = "<div>nothing here</div>\n"
assert(not pcall(run, { block_id = "block:b" }, {}))

-- Long scrollback is read from the end only, and only the newest lines count.
local lines = {}
for index = 1, 3000 do lines[index] = "<div>line " .. index .. " https://old.example/" .. index .. "</div>" end
html = table.concat(lines, "\n") .. "\n"
blob_calls = 0
pick_reply = { "1" }
run({ block_id = "block:b" }, {})
assert(#picked.items == 5 and picked.items[1].title == "old.example/3000" and picked.items[5].title == "old.example/2996")
assert(blob_calls > 0 and blob_calls < 40)
print("url picker ok")
