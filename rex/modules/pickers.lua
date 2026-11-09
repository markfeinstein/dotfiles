return function(context)
  local terminal_creator = context.terminal_creator
  local editor_processes = context.editor_processes
  local file_picker_shells = context.file_picker_shells
  local normalized_process_name = context.normalized_process_name
  local open_terminal_layer = context.open_terminal_layer
  local terminal_native_navigation_blocks = context.terminal_native_navigation_blocks
  local process_cwd = context.process_cwd
  local write_atomic = context.write_atomic
  local rex_picker = context.rex_picker
  local rex_gh_dash = context.rex_gh_dash
  local rex_capture = context.rex_capture
  local scrollback_editor = context.scrollback_editor
  local rex_lazygit = context.rex_lazygit
  local password_picker_enabled = context.password_picker_enabled
  local rose_pine_theme = context.rose_pine_theme
  local rose_pine_moon_theme = context.rose_pine_moon_theme
  local rose_pine_dawn_theme = context.rose_pine_dawn_theme
  local rose_pine_dark_theme = context.rose_pine_dark_theme
  local file_picker_focus_directory = (os.getenv("XDG_STATE_HOME")
    or (os.getenv("HOME") .. "/.local/state")) .. "/rex/file-picker-focus"

  local function file_picker_focus_path(block_id)
    local safe_block_id = block_id:gsub("[^%w._-]", "_")
    return file_picker_focus_directory .. "/" .. safe_block_id .. ".tsv"
  end

  local function remember_file_picker_focus(picker_block_id, session_id, source_block_id)
    local result, mkdir_err = rex.exec({ "mkdir", "-p", file_picker_focus_directory }, {
      timeout = 2,
      stdout = false,
      stderr = false,
    })
    if result == nil or not result.ok then
      rex.log("warn", "Unable to create the file picker focus directory: " .. tostring(mkdir_err))
      return
    end

    local path = file_picker_focus_path(picker_block_id)
    local written, write_err = write_atomic(path, function(file)
      file:write(session_id .. "\t" .. source_block_id .. "\n")
    end)
    if written == nil then
      rex.log("warn", "Unable to remember file picker focus: " .. tostring(write_err))
    end
  end

  local function find_floating_layer_by_label(view, label)
    for _, window in ipairs(view.windows or {}) do
      if window.window_id == view.active_window_id then
        for index = #(window.layers or {}), 1, -1 do
          local layer = window.layers[index]
          if layer.kind == "floating" then
            for _, block in ipairs(layer.blocks or {}) do
              if block.label == label then
                return layer
              end
            end
          end
        end
      end
    end
    return nil
  end

  local function is_block_zoomed(view, block_id)
    for _, window in ipairs(view.windows or {}) do
      if window.window_id == view.active_window_id then
        return window.zoomed_block_id == block_id
      end
    end
    return false
  end

  local function open_model_picker(ctx, restore_zoom)
    local command = { rex_picker, "pi-model", ctx.block_id }
    if restore_zoom then
      table.insert(command, "--restore-zoom")
    end
    local layer = open_terminal_layer(
      "Pi Model Picker",
      command,
      { 0.26, 0.28, 0.48, 0.44 }
    )
    for _, block_id in ipairs(layer.block_ids) do
      terminal_native_navigation_blocks[block_id] = true
    end
    return layer
  end

rex.action{
  name = "file_picker",
  title = "Open File Picker",
  description = "Choose files from a Nushell or Zsh prompt in a floating native picker.",
  category = "Pane",
  keywords = "file picker floating nushell zsh rust",
  run = function(ctx)
    if ctx.session_id == nil or ctx.block_id == nil then
      error("the file picker needs a focused terminal pane", 0)
    end

    local process, process_err = rex.block.call(terminal_creator, "process")
    if process == nil then
      error(process_err, 0)
    end

    local foreground_name = normalized_process_name(process.foreground)
    if foreground_name ~= nil and editor_processes[foreground_name] then
      -- Cmd+O is bound by Rex before the terminal sees it. Forward the
      -- equivalent CSI-u sequence so Neovim can resolve its <D-o> mapping.
      local written, write_err = rex.block.call(terminal_creator, "write", {
        data = "\27[111;9u",
      })
      if written == nil then
        error(write_err, 0)
      end
      return true
    end
    if foreground_name == nil or not file_picker_shells[foreground_name] then
      return false
    end

    local cwd = process_cwd(process)
    if cwd == nil then
      error("unable to determine the focused terminal's working directory", 0)
    end

    -- The picker exits inside its floating pane. Its built-in focus restoration
    -- runs before that pane closes, allowing Rex's close handling to select a
    -- sibling afterward. Restore the source only after Rex reports the close.
    local layer = open_terminal_layer(
      "File Picker",
      { rex_picker, "file", ctx.session_id, ctx.block_id, cwd, foreground_name, "--no-restore-focus" },
      { 0.08, 0.10, 0.84, 0.80 },
      cwd
    )
    for _, block_id in ipairs(layer.block_ids) do
      terminal_native_navigation_blocks[block_id] = true
      remember_file_picker_focus(block_id, ctx.session_id, ctx.block_id)
    end
    return layer
  end,
}

rex.action{
  name = "history_picker",
  title = "Search Nushell History",
  description = "Search the invoking Nushell prompt's history in a floating native picker.",
  category = "Pane",
  keywords = "history picker floating nushell rust",
  args = {
    database = "string",
    history_session = "integer",
    working_directory = "string",
    workspace = "string",
    result_file = "string",
    initial_query = "string",
  },
  run = function(ctx, args)
    if ctx.session_id == nil or ctx.block_id == nil then
      error("the history picker needs a focused terminal pane", 0)
    end

    local layer = open_terminal_layer(
      "History Picker",
      {
        rex_picker,
        "history",
        ctx.session_id,
        ctx.block_id,
        args.database,
        tostring(args.history_session),
        args.working_directory,
        args.workspace,
        args.result_file,
        args.initial_query,
      },
      { 0.08, 0.10, 0.84, 0.80 },
      args.working_directory
    )
    for _, block_id in ipairs(layer.block_ids) do
      terminal_native_navigation_blocks[block_id] = true
    end
    return layer
  end,
}

rex.action{
  name = "model_picker",
  title = "Select Pi Model",
  description = "Choose a model for the focused Pi session in a floating native picker.",
  category = "Pane",
  keywords = "pi model picker floating ai rust",
  run = function(ctx)
    if ctx.session_id == nil or ctx.block_id == nil then
      error("the Pi model picker needs a focused terminal pane", 0)
    end

    local view, view_err = rex.session.view{}
    if view == nil then
      error(view_err, 0)
    end
    local existing = find_floating_layer_by_label(view, "Pi Model Picker")
    if existing ~= nil then
      local closed, close_err = rex.session.close_layer{ layer_id = existing.layer_id }
      if closed == nil then
        error(close_err, 0)
      end
      return { layer_id = existing.layer_id, closed = true }
    end

    local process, process_err = rex.block.call(terminal_creator, "process")
    if process == nil then
      error(process_err, 0)
    end
    if normalized_process_name(process.foreground) ~= "pi" then
      return false
    end

    return open_model_picker(ctx, is_block_zoomed(view, ctx.block_id))
  end,
}

if password_picker_enabled then
  rex.action{
    name = "password_picker",
    title = "Copy Password",
    description = "Choose a pass entry by name and copy its first line without displaying the secret.",
    category = "Pane",
    keywords = "password pass secret clipboard picker floating",
    run = function(ctx)
      if ctx.session_id == nil or ctx.block_id == nil then
        error("the password picker needs a focused terminal pane", 0)
      end

      local layer = open_terminal_layer(
        "Password Store",
        { rex_picker, "password", "--origin-block", ctx.block_id },
        { 0.18, 0.18, 0.64, 0.64 }
      )
      for _, block_id in ipairs(layer.block_ids) do
        terminal_native_navigation_blocks[block_id] = true
      end
      return layer
    end,
  }
end

rex.action{
  name = "open_url_picker",
  title = "Open URL from Scrollback",
  description = "Choose an HTTP(S) URL from the focused terminal's newest 20,000 lines.",
  category = "Pane",
  keywords = "link picker browser scrollback rust",
  run = function(ctx)
    if ctx.session_id == nil or ctx.block_id == nil then
      error("the URL picker needs a focused terminal pane", 0)
    end

    return open_terminal_layer(
      "Open URL",
      { rex_picker, "url", ctx.session_id, ctx.block_id },
      { 0.25, 0.33, 0.50, 0.34 }
    )
  end,
}

rex.action{
  name = "edit_scrollback",
  title = "Open Scrollback in Editor",
  description = "Capture the focused terminal's screen and scrollback into read-only Neovim.",
  category = "Pane",
  keywords = "scrollback editor neovim copy search",
  run = function(ctx)
    if ctx.session_id == nil or ctx.block_id == nil then
      error("the scrollback editor needs a focused terminal pane", 0)
    end

    local command = [[
"$1" capture -s "$3" -b "$4" --trim --unwrap |
  exec "$2" -n -R --cmd 'set nomodeline' \
    -c 'setlocal buftype=nofile bufhidden=wipe noswapfile nomodified nomodeline' + -
]]
    return open_terminal_layer(
      "Scrollback Editor",
      {
        "/bin/bash",
        "-o",
        "pipefail",
        "-c",
        command,
        "rex-scrollback",
        rex_capture,
        scrollback_editor,
        ctx.session_id,
        ctx.block_id,
      },
      { 0.05, 0.05, 0.9, 0.9 }
    )
  end,
}

rex.action{
  name = "open_github_dashboard",
  title = "Open GitHub Dashboard",
  description = "Open gh-dash for the focused terminal's repository in a floating pane.",
  category = "Pane",
  keywords = "github pull request issue notification dashboard floating",
  run = function(ctx)
    if ctx.block_id == nil then
      error("the GitHub dashboard needs a focused terminal pane", 0)
    end

    local process, process_err = rex.block.call(terminal_creator, "process")
    if process == nil then
      error(process_err, 0)
    end

    local cwd = process_cwd(process)
    if cwd == nil then
      error("unable to determine the focused terminal's working directory", 0)
    end

    local layer = open_terminal_layer(
      "GitHub Dashboard",
      { rex_gh_dash },
      { 0.05, 0.05, 0.9, 0.9 },
      cwd
    )
    for _, block_id in ipairs(layer.block_ids) do
      terminal_native_navigation_blocks[block_id] = true
    end
    return layer
  end,
}

rex.action{
  name = "open_lazygit",
  title = "Open Lazygit",
  description = "Open lazygit in a floating pane, resolving bare repositories to a linked worktree.",
  category = "Pane",
  keywords = "git tui floating layer repository",
  run = function(ctx)
    if ctx.block_id == nil then
      error("lazygit needs a focused terminal pane", 0)
    end

    local process, process_err = rex.block.call(terminal_creator, "process")
    if process == nil then
      error(process_err, 0)
    end

    local cwd = process_cwd(process)
    if cwd == nil then
      error("unable to determine the focused terminal's working directory", 0)
    end

    return open_terminal_layer(
      "Lazygit",
      { rex_lazygit, cwd },
      { 0.05, 0.05, 0.9, 0.9 },
      cwd
    )
  end,
}

rex.action{
  name = "install_rose_pine_themes",
  title = "Install Rosé Pine Themes",
  description = "Import the complete official Rosé Pine family and select the managed light and dark variants.",
  category = "View",
  keywords = "appearance colors light dark theme",
  run = function()
    -- Import the unselected dark variant first, then Dawn, then the managed
    -- dark variant. The final light and dark imports become Rex's selected
    -- themes for their respective appearances.
    local other_dark_theme = rose_pine_theme
    if rose_pine_dark_theme == rose_pine_theme then
      other_dark_theme = rose_pine_moon_theme
    end
    rex.client.queue("client.theme.import", { path = other_dark_theme })
    rex.client.queue("client.theme.import", { path = rose_pine_dawn_theme })
    rex.client.queue("client.theme.import", { path = rose_pine_dark_theme })
    return {
      official = { rose_pine_theme, rose_pine_moon_theme, rose_pine_dawn_theme },
      selected = { light = rose_pine_dawn_theme, dark = rose_pine_dark_theme },
    }
  end,
}

end
