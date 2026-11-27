-- Run from the repository root with lua tests/rex/worktrees.lua.
local actions, picks, inputs, execs, queued, created = {}, {}, {}, {}, {}, {}
local pick_reply, input_reply = {}, {}
local cwd_by_block = {}
local view = { windows = {} }
local list_output = table.concat({
  "repo-root\t/h/dev/alpha\talpha\trepo root\t/h/dev/alpha/.git",
  "worktree\t/h/dev/alpha/main\talpha\tmain\t/h/dev/alpha/.git",
  "worktree\t/h/dev/alpha/feat-x\talpha\tfeat/x\t/h/dev/alpha/.git",
  "repo-root\t/h/dev/beta\tbeta\trepo root\t/h/dev/beta/.git",
  "worktree\t/h/dev/beta/main\tbeta\tmain\t/h/dev/beta/.git",
}, "\n") .. "\n"
local create_output = "/h/dev/beta/feat-new\n"

rex = {
  action = function(action) actions[action.name] = action.run end,
  ui = {
    pick = function(prompt) table.insert(picks, prompt); return pick_reply[1], pick_reply[2] end,
    input = function(prompt) table.insert(inputs, prompt); return input_reply[1], input_reply[2] end,
  },
  exec = function(argv)
    table.insert(execs, argv)
    if argv[2] == "list" then return { ok = true, stdout = list_output, stderr = "" } end
    return { ok = true, stdout = create_output, stderr = "" }
  end,
  block = { call = function(_, method, args)
    assert(method == "process")
    return { foreground = { cwd = cwd_by_block[args.block_id] } }
  end },
  session = {
    view = function() return view end,
    new_window = function(args) table.insert(created, args); return { window_id = "window:new" } end,
  },
  layout = { block = function(spec) return spec end },
  client = { queue = function(name, args) table.insert(queued, { name = name, args = args }) end },
}
dofile("rex/modules/prompts.lua")({
  terminal_creator = "com.superlogical.terminal",
  terminal_shell = "com.superlogical.terminal.shell",
  terminal_command = "/bin/nu",
  process_cwd = function(process) return process.foreground.cwd end,
  git_project = "/bin/git-project",
})
local switch, create = assert(actions.worktree_switch), assert(actions.worktree_create)

-- The current project's worktrees come first, marked "here".
cwd_by_block["block:me"] = "/h/dev/beta/main/src"
pick_reply = { "/h/dev/alpha/feat-x" }
local result = switch({ session_id = "s", block_id = "block:me" })
local items = picks[1].items
assert(#items == 3 and items[1].id == "/h/dev/beta/main" and items[1].detail == "here")
assert(items[2].title == "alpha · main" and items[3].title == "alpha · feat/x")
-- No tab is in that worktree, so a labeled tab opens there.
assert(result.opened and created[1].window_label == "alpha · feat/x")
assert(created[1].layout.options.cwd == "/h/dev/alpha/feat-x")
assert(created[1].layout.options.command[1] == "/bin/nu")
assert(created[1].layout.options.shell == "none")

-- An existing plain tab wins over an agent tab in the same worktree.
view = { windows = {
  { label = "Agent · alpha · feat/x · 1234abcd", layers = { { kind = "tiled", blocks = {
    { block_id = "block:agent", creator_name = "com.superlogical.terminal" } } } } },
  { label = "Floating tool", layers = { { kind = "floating", blocks = {
    { block_id = "block:float", creator_name = "com.superlogical.terminal" } } } } },
  { label = "alpha · feat/x", layers = { { kind = "tiled", blocks = {
    { block_id = "block:plain", creator_name = "com.superlogical.terminal" } } } } },
} }
cwd_by_block["block:agent"] = "/h/dev/alpha/feat-x"
cwd_by_block["block:float"] = "/h/dev/alpha/feat-x"
cwd_by_block["block:plain"] = "/h/dev/alpha/feat-x/lib"
result = switch({ session_id = "s", block_id = "block:me" })
assert(not result.opened and result.index == 3)
assert(queued[1].name == "client.tab.goto" and queued[1].args.index == 3)

-- Cancelling is quiet.
pick_reply = { nil, "cancelled" }
assert(switch({ session_id = "s", block_id = "block:me" }) == false)

-- Creating: pick the project, name the branch, run git-project, open a tab.
view = { windows = {} }
pick_reply = { "/h/dev/beta" }
input_reply = { "  feat/new " }
result = create({ session_id = "s", block_id = "block:me" })
local argv = execs[#execs]
assert(argv[1] == "/bin/git-project" and argv[2] == "worktree" and argv[4] == "feat/new")
assert(argv[5] == "--git-dir" and argv[6] == "/h/dev/beta/.git")
assert(picks[#picks].items[1].id == "/h/dev/beta")
assert(result.opened and created[#created].window_label == "beta · feat/new")

-- Unsafe branch names never reach git-project.
local before = #execs
input_reply = { "../escape" }
assert(not pcall(create, { session_id = "s", block_id = "block:me" }))
assert(#execs == before + 1) -- only the list call ran
print("worktrees ok")
