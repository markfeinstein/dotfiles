-- Run from the repository root with lua tests/rex/scratch.lua.
local actions = {}
local calls = { detach = 0, float = 0, focus = 0, move = 0, raise = 0, restore = 0 }
local scratch = nil
local scratch_layer = nil
local created
local started

local view = {
  active_window_id = "window:one",
  windows = {
    {
      window_id = "window:one",
      focused_block_id = "block:one",
      layers = {
        {
          kind = "tiled",
          blocks = { { block_id = "block:one" } },
        },
      },
    },
  },
}

local function active_window()
  for _, window in ipairs(view.windows) do
    if window.window_id == view.active_window_id then return window end
  end
end

local function remove_scratch()
  for _, window in ipairs(view.windows) do
    for index = #window.layers, 1, -1 do
      local layer = window.layers[index]
      for _, block in ipairs(layer.blocks or {}) do
        if scratch ~= nil and block.block_id == scratch.block_id then
          table.remove(window.layers, index)
          if window.focused_block_id == scratch.block_id then
            window.focused_block_id = (window.layers[1].blocks or {})[1].block_id
          end
          return
        end
      end
    end
  end
end

local function add_float(window, bounds, state)
  scratch_layer = {
    layer_id = "layer:scratch",
    kind = "floating",
    state = state or "normal",
    bounds = bounds,
    blocks = { scratch },
  }
  table.insert(window.layers, scratch_layer)
  scratch.placement = "placed"
  scratch.window_id = window.window_id
end

rex = {
  action = function(action) actions[action.name] = action.run end,
  log = function() end,
  layout = { block = function(spec) return spec end },
  block = {
    call = function(creator, method, args)
      assert(creator == "com.superlogical.terminal" and method == "process")
      assert(args.block_id == active_window().focused_block_id)
      return { foreground = { cwd = "/h/dev/project", name = "zsh" } }
    end,
  },
  exec = {
    start = function(argv, options)
      assert(options.stdout == false and options.stderr == false)
      started = argv
      return { pid = 1 }
    end,
  },
  session = {
    view = function() return view end,
    list_blocks = function() return { blocks = scratch and { scratch } or {} } end,
    new_layer = function(args)
      created = args
      scratch = {
        block_id = "block:scratch",
        label = args.layout.label,
        creator_name = "com.superlogical.terminal",
        flavor = args.layout.flavor,
        placement = "placed",
        window_id = args.window_id,
      }
      add_float(active_window(), args.bounds)
      active_window().focused_block_id = scratch.block_id
      return { block_ids = { scratch.block_id }, layer_id = scratch_layer.layer_id }
    end,
    detach_block = function(args)
      calls.detach = calls.detach + 1
      remove_scratch()
      scratch.placement = "detached"
      scratch.window_id = nil
      return { block_id = args.block_id }
    end,
    move_block = function(args)
      calls.move = calls.move + 1
      assert(args.block_id == scratch.block_id)
      scratch.placement = "placed"
      scratch.window_id = active_window().window_id
      return { revision = calls.move }
    end,
    float_block = function(args)
      calls.float = calls.float + 1
      remove_scratch()
      add_float(active_window(), args.bounds)
      return { layer_id = scratch_layer.layer_id }
    end,
    focus_block = function(args)
      calls.focus = calls.focus + 1
      active_window().focused_block_id = args.block_id
      return { revision = calls.focus }
    end,
    raise_layer = function(args)
      calls.raise = calls.raise + 1
      assert(args.layer_id == scratch_layer.layer_id)
      return { revision = calls.raise }
    end,
    set_layer_state = function(args)
      calls.restore = calls.restore + 1
      assert(args.layer_id == scratch_layer.layer_id and args.state == "normal" and args.focus)
      scratch_layer.state = "normal"
      active_window().focused_block_id = scratch.block_id
      return { revision = calls.restore }
    end,
  },
}

dofile("rex/modules/scratch.lua")({
  terminal_creator = "com.superlogical.terminal",
  terminal_shell = "com.superlogical.terminal.shell",
  terminal_command = "/nix/store/example-rex-nushell/bin/rex-nushell",
  rex_cli = "/bin/rex",
  process_cwd = function(process) return process.foreground.cwd end,
})
local toggle = assert(actions.toggle_scratch_terminal)

-- First use creates one managed Nushell float in the active tab.
local result = toggle({ session_id = "session:test", block_id = "block:one" })
assert(result.visible and result.block_id == scratch.block_id)
assert(created.window_id == "window:one" and created.focus == true)
assert(created.layout.options.command[1] == "/nix/store/example-rex-nushell/bin/rex-nushell")
assert(created.layout.options.shell == "none" and created.layout.options.cwd == "/h/dev/project")
assert(started[5] == "/bin/rex" and started[6] == "session:test" and started[7] == scratch.block_id)
assert(started[8]:find("exec /bin/sh %-c") and started[8]:find("rex%-nushell") and started[8]:find("/h/dev/project"))

-- Toggling the focused scratch fully detaches it; toggling again restores the same block.
scratch_layer.bounds = { 0.10, 0.20, 0.50, 0.60 }
result = toggle({ session_id = "session:test", block_id = scratch.block_id })
assert(not result.visible and scratch.placement == "detached" and calls.detach == 1)
result = toggle({ session_id = "session:test", block_id = "block:one" })
assert(result.visible and scratch.placement == "placed" and calls.move == 1 and calls.float == 1)
assert(scratch_layer.bounds[1] == 0.10 and scratch_layer.bounds[4] == 0.60)

-- If visible but unfocused, the toggle raises and focuses it instead of hiding it.
active_window().focused_block_id = "block:one"
result = toggle({ session_id = "session:test", block_id = "block:one" })
assert(result.visible and active_window().focused_block_id == scratch.block_id)
assert(calls.raise == 1 and calls.focus == 2)

-- A minimized scratch is restored and focused.
scratch_layer.state = "minimized"
active_window().focused_block_id = "block:one"
result = toggle({ session_id = "session:test", block_id = "block:one" })
assert(result.visible and scratch_layer.state == "normal" and calls.restore == 1)

-- The same scratch follows the session only when summoned from another tab.
view.windows[2] = {
  window_id = "window:two",
  focused_block_id = "block:two",
  layers = {
    {
      kind = "tiled",
      blocks = { { block_id = "block:two" } },
    },
  },
}
view.active_window_id = "window:two"
result = toggle({ session_id = "session:test", block_id = "block:two" })
assert(result.visible and scratch.window_id == "window:two")
assert(calls.detach == 2 and calls.move == 2 and calls.float == 2)
print("scratch ok")
