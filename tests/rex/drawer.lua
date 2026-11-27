-- Run from the repository root with lua tests/rex/drawer.lua.
local actions = {}
local created

local view = {
  active_window_id = "window:active",
  windows = {
    {
      window_id = "window:active",
      focused_block_id = "block:anchor",
      layers = {
        {
          kind = "tiled",
          blocks = { { block_id = "block:anchor" } },
        },
      },
    },
  },
}

rex = {
  action = function(action) actions[action.name] = action.run end,
  block = {
    call = function(creator, method)
      assert(creator == "com.superlogical.terminal" and method == "process")
      return { foreground = { cwd = "/h/dev/project" } }
    end,
  },
  layout = { block = function(spec) return spec end },
  session = {
    view = function() return view end,
    list_blocks = function() return { blocks = {} } end,
    new_layer = function(args)
      created = args
      return { block_ids = { "block:drawer" }, layer_id = "layer:drawer" }
    end,
  },
}

dofile("rex/modules/drawer.lua")({
  terminal_creator = "com.superlogical.terminal",
  terminal_shell = "com.superlogical.terminal.shell",
  terminal_drawer_command = "/nix/store/example-rex-nushell/bin/rex-nushell",
  terminal_drawer_label = "Terminal Drawer",
  terminal_drawer_presets = {},
  terminal_drawer_return_focus_by_session = {},
  copy_bounds = function(bounds) return bounds end,
  terminal_drawer_state = function()
    return { placement = "floating", bounds = { 0.68, 0.04, 0.30, 0.92 } }
  end,
  update_terminal_drawer_state = function() end,
  active_window = function(current_view) return current_view.windows[1] end,
  active_block_id = function(current_view) return current_view.windows[1].focused_block_id end,
  terminal_drawer_anchor_block_id = function() return "block:anchor" end,
  tiled_block_id = function() return "block:anchor" end,
  move_and_float = function() error("unexpected move") end,
  process_cwd = function(process) return process.foreground.cwd end,
})

local result = assert(actions.toggle_terminal_drawer)({ session_id = "session:test" })
assert(result.block_id == "block:drawer" and result.layer_id == "layer:drawer")
assert(created.window_id == "window:active" and created.focus == true)
assert(created.layout.flavor == "com.superlogical.terminal.shell")
assert(created.layout.options.shell == "none")
assert(created.layout.options.command[1] == "/nix/store/example-rex-nushell/bin/rex-nushell")
assert(created.layout.options.cwd == "/h/dev/project")
print("drawer ok")
