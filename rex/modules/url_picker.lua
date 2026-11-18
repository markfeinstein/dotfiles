-- Open or copy an HTTP(S) URL from the focused terminal's recent scrollback
-- in Rex's native prompt. This follows rex-picker's url adapter: plain URLs
-- and OSC 8 hyperlinks from the newest 20,000 lines, newest first.
--
-- Native prompts appear on every connected Rex app, so the prompt never
-- carries a full URL. Item ids are row numbers, titles drop the query and
-- fragment, and token-like path segments become "…". The full URL stays here.
return function(context)
  local terminal_creator = context.terminal_creator
  local line_limit = context.line_limit or 20000
  local open_bin = context.open_bin or "/usr/bin/open"
  local clipboard_bin = context.clipboard_bin or "/usr/bin/pbcopy"

  local M = {}

  local entities = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

  local function decode(text)
    return (text:gsub("&(#?x?)(%w+);", function(kind, body)
      if kind == "" then return entities[body] end
      local code = kind == "#x" and tonumber(body, 16) or (kind == "#" and tonumber(body) or nil)
      if code ~= nil and code < 128 then return string.char(code) end
      return nil
    end))
  end

  local function count_newlines(text)
    local _, count = text:gsub("\n", "")
    return count
  end

  -- Keeps the last `limit` lines; a final newline doesn't start another line.
  local function last_lines(text, limit)
    text = text:gsub("\n$", "")
    local total = count_newlines(text)
    if total < limit then return text end
    local skip, position = total - limit + 1, 0
    for _ = 1, skip do position = text:find("\n", position + 1, true) end
    return text:sub(position + 1)
  end

  -- Reads the end of the terminal's HTML until it holds line_limit lines,
  -- doubling the window and fetching only the newly exposed prefix.
  local function capture_html(block_id)
    local first, err = rex.block.call(terminal_creator, "format", {
      block_id = block_id, format = "html", trim = true, unwrap = true, max_bytes = 1024,
    })
    if first == nil then error("Unable to read the terminal: " .. tostring(err), 0) end
    if first.id == nil or first.total == nil then return last_lines(first.content or "", line_limit) end

    local function read(start, finish)
      local parts, offset = {}, start
      while offset < finish do
        local chunk, read_err = rex.block.call(terminal_creator, "blob_read", {
          block_id = block_id, id = first.id, offset = offset, max_bytes = math.min(983040, finish - offset),
        })
        if chunk == nil then error("Unable to read the terminal: " .. tostring(read_err), 0) end
        local data = chunk.data or ""
        if data == "" then
          if chunk.eof then break end
          error("The terminal's scrollback stopped part way", 0)
        end
        table.insert(parts, data)
        offset = offset + #data
        if chunk.eof then break end
      end
      local text = table.concat(parts)
      if offset > finish then text = text:sub(1, #text - (offset - finish)) end
      return text
    end

    local total = first.total
    local start = math.max(0, total - 65536)
    local suffix = read(start, total)
    local newlines = count_newlines(suffix)
    while start > 0 and newlines < line_limit do
      local next_start = math.max(0, total - 2 * (total - start))
      local prefix = read(next_start, start)
      newlines = newlines + count_newlines(prefix)
      suffix = prefix .. suffix
      start = next_start
    end
    return last_lines(suffix, line_limit)
  end

  local function valid_url(url)
    if url == nil or url == "" or url:find("[%c%s]") then return false end
    local lowered = url:lower()
    local rest = lowered:match("^https?://(.*)$")
    if rest == nil then return false end
    local authority = rest:match("^([^/?#]*)")
    local host = authority:gsub("^.*@", ""):gsub(":%d*$", "")
    return host ~= "" and not host:find("[^%w%.%-%[%]:_]")
  end

  local closers = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

  local function count(text, character)
    local _, found = text:gsub("%" .. character, "")
    return found
  end

  -- Drops sentence punctuation and unbalanced closing brackets from the end.
  function M.clean_visible_url(value)
    local candidate = value:gsub("^%s+", ""):gsub("%s+$", "")
    while candidate ~= "" do
      local last = candidate:sub(-1)
      local opener = closers[last]
      if last:find("^[%.,;:!%?]$") or (opener ~= nil and count(candidate, last) > count(candidate, opener)) then
        candidate = candidate:sub(1, -2)
      else
        break
      end
    end
    return valid_url(candidate) and candidate or nil
  end

  local function clean_label(value)
    local label = value:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if label == "" or M.clean_visible_url(label) == label then return nil end
    -- Count characters, not bytes, so a cut never splits one.
    local characters = {}
    for character in label:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      table.insert(characters, character)
    end
    if #characters > 56 then label = table.concat(characters, "", 1, 55) .. "…" end
    return label
  end

  -- Returns unique URLs newest first, each { url = …, label = … }.
  function M.extract(html)
    local text_parts, text_length, events = {}, 0, {}
    local active
    local function add_text(raw)
      local decoded = decode(raw)
      table.insert(text_parts, decoded)
      text_length = text_length + #decoded
      if active ~= nil then active.label = active.label .. decoded end
    end
    local function close_link()
      if active == nil then return end
      local url = active.href:gsub("^%s+", ""):gsub("%s+$", "")
      if valid_url(url) then
        table.insert(events, { position = active.position, url = url, label = clean_label(active.label) })
      end
      active = nil
    end

    local position = 1
    while position <= #html do
      local open = html:find("<", position, true)
      if open == nil then add_text(html:sub(position)); break end
      if open > position then add_text(html:sub(position, open - 1)) end
      local close = html:find(">", open, true)
      if close == nil then break end
      local tag = html:sub(open + 1, close - 1)
      local name = tag:match("^/?(%a+)")
      if name ~= nil and name:lower() == "a" then
        if tag:sub(1, 1) == "/" then
          close_link()
        else
          close_link()
          local href = tag:match('href%s*=%s*"([^"]*)"') or tag:match("href%s*=%s*'([^']*)'")
          if href ~= nil then active = { position = text_length, href = decode(href), label = "" } end
        end
      end
      position = close + 1
    end
    close_link()

    local text = table.concat(text_parts)
    local search = 1
    while true do
      local first, last = text:find("[Hh][Tt][Tt][Pp][Ss]?://[^%s<>\"']+", search)
      if first == nil then break end
      local url = M.clean_visible_url(text:sub(first, last))
      if url ~= nil then table.insert(events, { position = first - 1, url = url }) end
      search = last + 1
    end

    table.sort(events, function(a, b)
      if a.position ~= b.position then return a.position > b.position end
      return a.label ~= nil and b.label == nil
    end)
    local seen, candidates = {}, {}
    for _, event in ipairs(events) do
      if not seen[event.url] then
        seen[event.url] = true
        table.insert(candidates, { url = event.url, label = event.label })
      end
    end
    return candidates
  end

  -- Long segments that switch between letters and digits often are tokens,
  -- ids, or signatures; readable words and short numbers stay.
  local function token_like(segment)
    if #segment < 16 or segment:find("[^%w_%-%.~]") then return false end
    local switches, previous = 0, nil
    for character in segment:gmatch(".") do
      local kind = character:find("%d") and "d" or (character:find("%a") and "a" or previous)
      if previous ~= nil and kind ~= previous then switches = switches + 1 end
      previous = kind
    end
    return switches >= 4
  end

  -- What other devices see: host and path, without query, fragment, user
  -- info, or token-like path segments.
  function M.display(url)
    local rest = url:match("^[Hh][Tt][Tt][Pp][Ss]?://(.*)$") or url
    local authority, path = rest:match("^([^/?#]*)(.*)$")
    authority = authority:gsub("^.*@", "")
    local query = path:find("[?#]")
    local hidden = query ~= nil
    if query ~= nil then path = path:sub(1, query - 1) end
    path = path:gsub("[^/]+", function(segment)
      if token_like(segment) then return "…" end
      return nil
    end)
    if path == "" then path = "/" end
    return authority .. path .. (hidden and "?…" or "")
  end

  function M.items(candidates)
    local items = {}
    for index, candidate in ipairs(candidates) do
      local shown = M.display(candidate.url)
      table.insert(items, {
        id = tostring(index),
        title = candidate.label or shown,
        subtitle = candidate.label and shown or nil,
        icon = "link",
      })
    end
    return items
  end

  local modes = {
    open = "Open URL from scrollback",
    background = "Open URL in the background",
    copy = "Copy URL from scrollback",
  }

  local function act(mode, url)
    local result, err
    if mode == "copy" then
      result, err = rex.exec({ clipboard_bin }, { stdin = url, timeout = 5, stdout = false, stderr = false })
    elseif mode == "background" then
      result, err = rex.exec({ open_bin, "-g", url }, { timeout = 5, stdout = false, stderr = false })
    else
      result, err = rex.exec({ open_bin, url }, { timeout = 5, stdout = false, stderr = false })
    end
    if result == nil or not result.ok then
      error("Unable to " .. (mode == "copy" and "copy" or "open") .. " the URL: " .. tostring(err or result.code), 0)
    end
  end

  rex.action{
    name = "open_url_picker",
    title = "Open URL from Scrollback",
    description = "Choose an HTTP(S) URL from the focused terminal's newest 20,000 lines in a native picker, "
      .. "then open it (mode=background keeps the browser behind) or copy it (mode=copy).",
    category = "Pane",
    keywords = "link url picker browser scrollback open copy native",
    args = { mode = "string?" },
    run = function(ctx, args)
      local mode = (args and args.mode) or "open"
      if modes[mode] == nil then error("mode must be open, background, or copy", 0) end
      if ctx.block_id == nil then error("the URL picker needs a focused terminal pane", 0) end
      local candidates = M.extract(capture_html(ctx.block_id))
      if #candidates == 0 then
        -- Rex has no notice API for actions, so say so in the picker itself
        -- rather than failing. It closes itself like a notice; choosing the
        -- row or pressing Escape closes it sooner.
        rex.ui.pick{
          title = "No links in this pane",
          placeholder = "Closes by itself",
          items = { {
            id = "none",
            title = "No HTTP or HTTPS links in the last " .. line_limit .. " lines",
            subtitle = "Full-screen programs such as Pi and Neovim keep only what's on screen",
            icon = "link",
          } },
          timeout = 3,
        }
        return false
      end
      local chosen, why, detail = rex.ui.pick{
        title = modes[mode],
        placeholder = "Filter by link text, host, or path",
        items = M.items(candidates),
      }
      if chosen == nil then
        if why == "cancelled" then return false end
        error("Unable to show the URL picker: " .. tostring(why) .. " " .. tostring(detail or ""), 0)
      end
      local candidate = candidates[tonumber(chosen)]
      if candidate == nil then error("Unknown URL choice", 0) end
      act(mode, candidate.url)
      return true
    end,
  }

  return M
end
