return function(context)
  local terminal_creator = context.terminal_creator
  local editor_processes = context.editor_processes
  local file_picker_shells = context.file_picker_shells
  local normalized_process_name = context.normalized_process_name
  local open_terminal_layer = context.open_terminal_layer
  local terminal_native_navigation_blocks = context.terminal_native_navigation_blocks
  local process_cwd = context.process_cwd
  local rex_picker = context.rex_picker
  local rex_gh_dash = context.rex_gh_dash
  local rex_capture = context.rex_capture
  local scrollback_editor = context.scrollback_editor
  local rex_lazygit = context.rex_lazygit
  local password_picker_enabled = context.password_picker_enabled

  local function open_picker(_ctx, label, command, bounds, cwd)
    local layer = open_terminal_layer(label, command, bounds, cwd)
    for _, id in ipairs(layer.block_ids) do
      terminal_native_navigation_blocks[id] = true
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

    return open_picker(ctx, "File Picker",
      { rex_picker, "file", ctx.session_id, ctx.block_id, cwd, foreground_name },
      { 0.08, 0.10, 0.84, 0.80 }, cwd)
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

    return open_picker(ctx,
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

      return open_picker(ctx,
        "Password Store",
        { rex_picker, "password", "--origin-block", ctx.block_id },
        { 0.18, 0.18, 0.64, 0.64 }
      )
    end,
  }
end

-- Native prompts fan out to all eligible clients. This opt-in pilot only
-- offers fixed public docs; never pass raw scrollback or other user data here.
rex.action{
  name = "rex_docs_picker",
  title = "Open Rex Documentation…",
  category = "Help",
  run = function()
    if not rex.ui or not rex.ui.pick then
      error("This action requires a Rex server and app with native prompt support", 0)
    end
    local items = {
      { id = "customize/custom-ui", title = "Custom UI", icon = "document" },
      { id = "reference/api", title = "Server API", icon = "server" },
      { id = "reference/cli", title = "CLI Reference", icon = "terminal" },
    }
    local id, why = rex.ui.pick{ title = "Rex documentation", placeholder = "Filter pages", items = items }
    if not id then
      if why == "cancelled" then return false end
      error("Unable to show documentation picker: " .. tostring(why), 0)
    end
    for _, page in ipairs(items) do
      if id == page.id then
        rex.client.queue("client.url.open", {
          url = "https://www.superlogical.com/rex/docs/" .. page.id,
        })
        return true
      end
    end
    error("Unknown documentation page", 0)
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

end
