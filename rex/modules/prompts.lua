-- Actions built on Rex's native prompts (rex.ui.input and rex.ui.pick).
-- Prompts appear on every connected Rex app, including phones, so never put
-- scrollback, history, passwords, or other private text in them.
return function(context)
  local terminal_creator = context.terminal_creator
  local terminal_shell = context.terminal_shell
  local process_cwd = context.process_cwd
  local normalized_process_name = context.normalized_process_name
  local git_project = context.git_project
  local home = os.getenv("HOME") or ""

  local function prompt_failure(why, detail)
    return { status = why, detail = detail }
  end

  local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
  end

  local function abbreviate(path)
    if home ~= "" and path:sub(1, #home) == home then
      return "~" .. path:sub(#home + 1)
    end
    return path
  end

  local function inside(path, root)
    return path == root or path:sub(1, #root + 1) == root .. "/"
  end

  local function block_cwd(block_id)
    if block_id == nil then return nil end
    local process = rex.block.call(terminal_creator, "process", { block_id = block_id })
    return process and process_cwd(process) or nil
  end

  -- git-project lists every project under ~/dev as tab-separated rows:
  -- kind, path, project, space (the branch for a worktree), common Git dir.
  local function list_projects()
    local result, err = rex.exec({ git_project, "list" }, { timeout = 15 })
    if result == nil then error("Unable to run git-project: " .. tostring(err), 0) end
    if not result.ok then error("git-project list failed: " .. trim(result.stderr), 0) end
    local worktrees, roots = {}, {}
    for line in result.stdout:gmatch("[^\n]+") do
      local kind, path, project, space, git_dir =
        line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
      if kind == "worktree" then
        table.insert(worktrees, { path = path, project = project, branch = space })
      elseif kind == "repo-root" then
        table.insert(roots, { path = path, project = project, git_dir = git_dir })
      end
    end
    return worktrees, roots
  end

  -- Prefer a plain tab whose pane already sits in the worktree; fall back to
  -- an agent tab there. Floating layers, such as the drawer, don't count.
  local function find_window(session_id, path)
    local view = rex.session.view{ session_id = session_id }
    if view == nil then return nil end
    local fallback
    for index, window in ipairs(view.windows or {}) do
      local label = window.label or ""
      local agent = label:find("^Agent · ") ~= nil or label:find("^subagent%-") ~= nil
      for _, layer in ipairs(window.layers or {}) do
        if layer.kind ~= "floating" then
          for _, block in ipairs(layer.blocks or {}) do
            local cwd = block.creator_name == terminal_creator and block_cwd(block.block_id) or nil
            if cwd ~= nil and inside(cwd, path) then
              if not agent then return index end
              fallback = fallback or index
            end
          end
        end
      end
    end
    return fallback
  end

  local function open_worktree(ctx, path, label)
    local index = find_window(ctx.session_id, path)
    if index ~= nil then
      local ok = rex.invoke("tab_goto_with_terminal_drawer", { index = index })
      if not ok then rex.client.queue("client.tab.goto", { index = index }) end
      return { path = path, opened = false, index = index }
    end
    local created, err = rex.session.new_window{
      session_id = ctx.session_id,
      window_label = label,
      layout = rex.layout.block{ flavor = terminal_shell, options = { cwd = path } },
    }
    if created == nil then error("Unable to open a tab for " .. path .. ": " .. tostring(err), 0) end
    return { path = path, opened = true, window_id = created.window_id }
  end

  local function project_of(path, roots)
    for _, root in ipairs(roots) do
      if inside(path, root.path) then return root.project end
    end
    return nil
  end

  -- The Pi model list in a native prompt. It talks to the rex-model-picker
  -- extension's bridge socket, as the older floating rex-picker one does.
  -- Model names and prices are not private.
  local model_markers = { "✓ ", "★ ", "◆ " }

  local function model_socket(block_id)
    local state = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
    local safe = block_id:gsub("^block:", "")
    safe = safe:gsub("[^%w._-]", "_")
    return state .. "/pi/model-picker/" .. safe .. ".sock"
  end

  local function model_bridge(socket, request)
    local result, err = rex.exec({ "/usr/bin/nc", "-U", socket }, { stdin = request .. "\n", timeout = 5 })
    if result == nil then error("Unable to reach Pi: " .. tostring(err), 0) end
    local reply = result.stdout
    if reply:sub(1, 6) == "error\t" then error("Pi: " .. trim(reply:sub(7)), 0) end
    if reply:sub(1, 2) ~= "ok" then error("Pi's model picker did not answer", 0) end
    return reply
  end

  local function split_columns(text)
    local columns = {}
    for column in (text .. "  "):gmatch("(.-)%s%s+") do
      if column ~= "" then table.insert(columns, column) end
    end
    return columns
  end

  local function model_items(reply)
    local items = {}
    local first = true
    for line in reply:gmatch("[^\n]+") do
      if first then
        first = false
      else
        local key, select, display = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
        if key ~= nil then
          -- Drop the hidden search text, then the colors.
          display = display:gsub("\27%[8m.*$", "")
          display = display:gsub("\27%[[%d;]*m", "")
          local columns = split_columns(trim(display))
          local name, current = columns[1] or select, false
          local stripped = true
          while stripped do
            stripped = false
            for _, marker in ipairs(model_markers) do
              if name:sub(1, #marker) == marker then
                current = current or marker == model_markers[1]
                name = name:sub(#marker + 1)
                stripped = true
              end
            end
          end
          local ids = rex.json.decode(key) or {}
          -- Columns 7 and 8 hold an icon when the model reasons or reads
          -- images, and a dash when it doesn't.
          local abilities = {}
          if columns[7] ~= nil and columns[7] ~= "\226\128\148" then table.insert(abilities, "thinking") end
          if columns[8] ~= nil and columns[8] ~= "\226\128\148" then table.insert(abilities, "images") end
          -- A leading "!" marks a window smaller than the session's context.
          local context_size = tostring(columns[3] or "?"):gsub("^!(.*)$", "%1 (too small)")
          table.insert(items, {
            id = select,
            title = name,
            subtitle = table.concat({
              tostring(ids[1] or columns[2] or "?"),
              context_size .. " context",
              tostring(columns[4] or "?") .. " output",
              #abilities > 0 and table.concat(abilities, ", ") or nil,
            }, " · "),
            detail = trim((columns[5] or "") .. " / " .. trim(columns[6] or "")),
            icon = current and "star" or nil,
          })
        end
      end
    end
    return items
  end

  rex.action{
    name = "model_picker",
    title = "Select Pi Model",
    description = "Choose a model for the focused Pi session in Rex's native prompt.",
    category = "Pane",
    keywords = "pi model picker native ai",
    run = function(ctx)
      if ctx.block_id == nil then error("the model picker needs a focused Pi pane", 0) end
      -- Like the floating picker, do nothing outside a Pi pane.
      local process = rex.block.call(terminal_creator, "process", { block_id = ctx.block_id })
      if process == nil or normalized_process_name(process.foreground) ~= "pi" then
        return false
      end
      local socket = model_socket(ctx.block_id)
      -- Without a scope, Pi lists its enabledModels when they're set, or every
      -- model when they aren't.
      local reply = model_bridge(socket, '{"action":"list"}')
      local items = model_items(reply)
      if #items == 0 then error("Pi listed no models", 0) end
      -- Pi refuses a switch mid-turn, so say so before anyone chooses.
      local busy = reply:match("^[^\n]*;idle=0[;\t\n]") ~= nil
      local select, why, detail = rex.ui.pick{
        title = busy and "Pi model (Pi is busy; switch after this turn)" or "Pi model",
        placeholder = "Filter models",
        items = items,
      }
      if select == nil then
        if why == "cancelled" then return false end
        error("Unable to show the model picker: " .. tostring(why) .. " " .. tostring(detail or ""), 0)
      end
      model_bridge(socket, select)
      return true
    end,
  }

  -- Worktree paths and branch names appear on every connected app.
  rex.action{
    name = "worktree_switch",
    title = "Switch to Worktree…",
    description = "Pick a worktree under ~/dev and go to its tab, or open a new tab there.",
    category = "Tab",
    keywords = "worktree branch project repo switch git",
    run = function(ctx)
      local worktrees, roots = list_projects()
      if #worktrees == 0 then error("git-project found no worktrees", 0) end
      local here = block_cwd(ctx.block_id)
      local current_project = here and project_of(here, roots) or nil
      local items, by_path = {}, {}
      local function add(worktree)
        local current = here ~= nil and inside(here, worktree.path)
        table.insert(items, {
          id = worktree.path,
          title = worktree.project .. " · " .. worktree.branch,
          subtitle = abbreviate(worktree.path),
          icon = "branch",
          detail = current and "here" or nil,
        })
        by_path[worktree.path] = worktree
      end
      for _, worktree in ipairs(worktrees) do
        if worktree.project == current_project then add(worktree) end
      end
      for _, worktree in ipairs(worktrees) do
        if worktree.project ~= current_project then add(worktree) end
      end

      local path, why, detail = rex.ui.pick{
        title = "Switch to worktree",
        placeholder = "Filter by project or branch",
        items = items,
      }
      if path == nil then
        if why == "cancelled" then return false end
        error("Unable to show the worktree picker: " .. tostring(why) .. " " .. tostring(detail or ""), 0)
      end
      local worktree = by_path[path]
      return open_worktree(ctx, path, worktree.project .. " · " .. worktree.branch)
    end,
  }

  rex.action{
    name = "worktree_create",
    title = "New Worktree…",
    description = "Pick a project under ~/dev, name a branch, create its worktree with git-project, and open a tab there.",
    category = "Tab",
    keywords = "worktree branch project repo new create git",
    run = function(ctx)
      local _, roots = list_projects()
      if #roots == 0 then error("git-project found no projects", 0) end
      local here = block_cwd(ctx.block_id)
      local items, by_path = {}, {}
      local function add(root)
        local current = here ~= nil and inside(here, root.path)
        table.insert(items, {
          id = root.path,
          title = root.project,
          subtitle = abbreviate(root.path),
          icon = "folder",
          detail = current and "here" or nil,
        })
        by_path[root.path] = root
      end
      for _, root in ipairs(roots) do
        if here ~= nil and inside(here, root.path) then add(root) end
      end
      for _, root in ipairs(roots) do
        if not (here ~= nil and inside(here, root.path)) then add(root) end
      end

      local root_path, why, detail = rex.ui.pick{
        title = "New worktree in…",
        placeholder = "Filter projects",
        items = items,
      }
      if root_path == nil then
        if why == "cancelled" then return false end
        error("Unable to show the project picker: " .. tostring(why) .. " " .. tostring(detail or ""), 0)
      end
      local root = by_path[root_path]

      local branch
      branch, why, detail = rex.ui.input{
        title = "Branch for the new " .. root.project .. " worktree",
        placeholder = "feat/short-name",
        confirm = "Create worktree",
      }
      if branch == nil then
        if why == "cancelled" then return false end
        error("Unable to ask for a branch: " .. tostring(why) .. " " .. tostring(detail or ""), 0)
      end
      branch = trim(branch)
      if not branch:match("^[A-Za-z0-9][A-Za-z0-9._/-]*$") or branch:find("..", 1, true) then
        error("Not a usable branch name: " .. branch, 0)
      end

      -- An existing branch gets a worktree as is; a new one starts from the
      -- default branch, as git-project and Worktrunk decide.
      local result, err = rex.exec({ git_project, "worktree", "--branch", branch, "--git-dir", root.git_dir },
        { timeout = 180 })
      if result == nil then error("Unable to run git-project: " .. tostring(err), 0) end
      if not result.ok then error("git-project could not create the worktree: " .. trim(result.stderr), 0) end
      local path
      for line in result.stdout:gmatch("[^\n]+") do path = trim(line) end
      if path == nil or path:sub(1, 1) ~= "/" then
        error("git-project did not report the new worktree's path", 0)
      end
      return open_worktree(ctx, path, root.project .. " · " .. branch)
    end,
  }

  -- Agents run this with `rex do ask_user question=... options=...`, and the
  -- answer comes back as the action's JSON result. A missing answer is a
  -- result too, so a caller can tell a cancel from a timeout.
  rex.action{
    name = "ask_user",
    title = "Ask the User…",
    description = "Ask a question on every connected Rex app and return the answer. Meant for agents through rex do; "
      .. "the question is visible on every device, so it must not contain secrets.",
    category = "Agents",
    keywords = "agent question prompt answer approve choose",
    args = {
      question = "string",
      options = "array?",
      placeholder = "string?",
      value = "string?",
      confirm = "string?",
      allow_other = "boolean?",
      multiple = "boolean?",
      timeout = "integer?",
    },
    run = function(_ctx, args)
      if not rex.ui or not rex.ui.pick then
        return prompt_failure("unsupported", "This Rex server has no native prompts")
      end
      local question = args.question
      if type(question) ~= "string" or question == "" then
        error("ask_user needs a question", 0)
      end
      local timeout = args.timeout
      if timeout ~= nil and (timeout < 1 or timeout > 3600) then
        error("timeout must be between 1 and 3600 seconds", 0)
      end

      local options = args.options or {}
      if #options == 0 then
        local text, why, detail = rex.ui.input{
          title = question,
          placeholder = args.placeholder,
          value = args.value,
          confirm = args.confirm,
          timeout = timeout,
        }
        if text == nil then return prompt_failure(why, detail) end
        return { status = "answered", answer = text }
      end

      local answer, why, detail = rex.ui.pick{
        title = question,
        placeholder = args.placeholder,
        value = args.value,
        confirm = args.confirm,
        items = options,
        allow_other = args.allow_other == true,
        multiple = args.multiple == true,
        timeout = timeout,
      }
      if answer == nil then return prompt_failure(why, detail) end
      if type(answer) == "table" and answer.text ~= nil then
        return { status = "answered", answer = answer.text, other = true }
      end
      return { status = "answered", answer = answer }
    end,
  }
end
