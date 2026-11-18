-- Actions built on Rex's native prompts (rex.ui.input and rex.ui.pick).
-- Prompts appear on every connected Rex app, including phones, so never put
-- scrollback, history, passwords, or other private text in them.
return function(context)
  local terminal_shell = context.terminal_shell

  local function prompt_failure(why, detail)
    return { status = why, detail = detail }
  end

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
