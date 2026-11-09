-- CodeCompanion chat and inline coding assistant.

local codecompanion_loaded = false
local copilot_setup_done = false
local copilot_pending = nil
local copilot_restart_needed = false
local lazy = require("mark.lazy")
local log = require("mark.log").get("codecompanion")

local copilot_command_actions = {
	attach = true,
	detach = true,
	disable = true,
	enable = true,
	toggle = true,
	version = true,
}

local function is_copilot_command_action(args)
	local params = vim.split(args or "", "%s+", { trimempty = true })
	return copilot_command_actions[params[1]] == true
end

local function restart_copilot_client(client)
	if type(client.teardown) == "function" then
		pcall(client.teardown)
	elseif client.id then
		local lsp_client = vim.lsp.get_client_by_id(client.id)
		if lsp_client then
			lsp_client:stop(true)
		end
		client.id = nil
	end

	client.client_starting = false
	client.setup_pending = false
	client.startup_error = nil
	client.initialized = false

	if type(client.setup) == "function" then
		client.setup()
	end
end

local function ensure_copilot(trigger, before_setup)
	if copilot_setup_done then
		local client = lazy.require("copilot.client", { log = false })
		if client and type(client.setup) == "function" and (client.startup_error or copilot_restart_needed) then
			if before_setup and not before_setup() then
				return false
			end
			if copilot_restart_needed then
				restart_copilot_client(client)
			else
				client.setup()
			end
			copilot_restart_needed = false
		end
		return true
	end

	if package.loaded["copilot"] == nil then
		local ok = lazy.packadd("copilot.lua", { notify = true, trigger = trigger or ":Copilot" })
		if not ok then
			return false
		end
	end

	local copilot = lazy.require("copilot", { notify = true })
	if not copilot then
		return false
	end

	if before_setup and not before_setup() then
		return false
	end

	-- NES and the binary server are copilot.lua defaults. Suggestion keymaps are
	-- only installed while suggestions are enabled, so disabling them is enough.
	local ok, err = pcall(copilot.setup, {
		panel = { enabled = false },
		suggestion = { enabled = false },
		should_attach = function()
			return false
		end,
	})
	if not ok then
		vim.notify("Failed to set up copilot.lua: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	copilot_setup_done = true
	return true
end

local create_copilot_proxy

local function restore_copilot_command()
	pcall(vim.api.nvim_del_user_command, "Copilot")
	local files = vim.api.nvim_get_runtime_file("plugin/copilot.lua", false)
	if #files == 0 then
		vim.notify("Failed to find copilot.lua command", vim.log.levels.ERROR)
		return false
	end

	local ok, err = pcall(vim.cmd.source, vim.fn.fnameescape(files[1]))
	if not ok then
		vim.notify("Failed to restore copilot.lua command: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	return vim.api.nvim_get_commands({ builtin = false }).Copilot ~= nil
end

local function clear_copilot_pending()
	if copilot_pending and copilot_pending.timer then
		copilot_pending.timer:stop()
		copilot_pending.timer:close()
	end
	copilot_pending = nil
end

local function fail_copilot_pending(message)
	clear_copilot_pending()
	create_copilot_proxy()
	vim.notify(message .. "; retry :Copilot", vim.log.levels.ERROR)
end

local function replay_copilot_command(command)
	local ok, err = pcall(vim.api.nvim_cmd, command)
	if not ok then
		create_copilot_proxy()
		vim.notify("Failed to replay :Copilot command: " .. tostring(err), vim.log.levels.ERROR)
	end
	return ok
end

local function prepare_copilot_replay(command)
	local client_config = lazy.require("copilot.client.config", { log = false })
	if not client_config or type(client_config.add_callback) ~= "function" then
		vim.notify("Failed to load copilot.lua client callback helper", vim.log.levels.ERROR)
		return false
	end

	copilot_pending = {
		command = command,
		replayed = false,
	}
	local pending = copilot_pending

	client_config.add_callback(function()
		if copilot_pending ~= pending or pending.replayed then
			return
		end

		pending.replayed = true
		clear_copilot_pending()
		if not restore_copilot_command() then
			create_copilot_proxy()
			return
		end
		replay_copilot_command(command)
	end)

	return true
end

local function start_copilot_watch(command)
	if not copilot_pending then
		return
	end

	local client = lazy.require("copilot.client", { log = false })
	if not client then
		fail_copilot_pending("Failed to load copilot.lua client")
		return
	end

	local timeout_ms = 10000
	-- Raw libuv timers use the loop's cached clock; refresh it so prior
	-- event-loop blocking cannot shorten the startup timeout.
	vim.uv.update_time()
	local started_at = vim.uv.now()
	local timer = vim.uv.new_timer()
	if copilot_pending then
		copilot_pending.timer = timer
	end

	local function check_startup()
		if not copilot_pending or copilot_pending.command ~= command or copilot_pending.timer ~= timer then
			return
		end

		if client.startup_error then
			fail_copilot_pending("Copilot failed to start: " .. tostring(client.startup_error))
			return
		end

		if vim.uv.now() - started_at >= timeout_ms then
			copilot_restart_needed = true
			fail_copilot_pending("Timed out waiting for Copilot to initialize")
		end
	end

	timer:start(50, 50, vim.schedule_wrap(check_startup))
end

create_copilot_proxy = function()
	vim.api.nvim_create_user_command("Copilot", function(opts)
		if copilot_pending then
			vim.notify("Copilot is still starting; ignoring duplicate :Copilot command", vim.log.levels.WARN)
			return
		end

		local command = {
			cmd = "Copilot",
			args = opts.args == "" and {} or { opts.args },
			bang = opts.bang,
			magic = { bar = false, file = false },
		}
		if opts.smods then
			command.mods = opts.smods
		end

		local wait_for_ready = not is_copilot_command_action(opts.args)
		local function before_setup()
			if wait_for_ready then
				return prepare_copilot_replay(command)
			end
			return true
		end

		pcall(vim.api.nvim_del_user_command, "Copilot")
		if not ensure_copilot(":Copilot", before_setup) then
			clear_copilot_pending()
			create_copilot_proxy()
			vim.notify("Failed to load copilot.lua; retry :Copilot", vim.log.levels.ERROR)
			return
		end

		if not wait_for_ready then
			if not restore_copilot_command() then
				create_copilot_proxy()
				return
			end
			replay_copilot_command(command)
			return
		end

		if not copilot_pending then
			return
		end

		-- copilot.lua creates the real :Copilot command while loading. Replace it
		-- with the proxy until the LSP initialize/on_init path has completed so a
		-- second invocation cannot race ahead of the queued replay.
		create_copilot_proxy()
		start_copilot_watch(command)
	end, {
		nargs = "?",
		bang = true,
		desc = "Load copilot.lua and forward to :Copilot after client initialization",
	})
end

if package.loaded["copilot"] == nil then
	create_copilot_proxy()
end

local function ensure_blink_completion(trigger)
	local ensure_blink = rawget(_G, "_ensure_blink_cmp")
	if type(ensure_blink) ~= "function" then
		return false
	end

	local ok, available = pcall(ensure_blink, trigger or "CodeCompanion completion")
	if not ok then
		log.error("failed to load blink.cmp for CodeCompanion completion", available)
		vim.notify(
			"Failed to load blink.cmp for CodeCompanion completion: " .. tostring(available),
			vim.log.levels.ERROR
		)
		return false
	end

	return available == true
end

local function codecompanion_source_buffer_context(chat)
	if type(chat) ~= "table" or type(chat.opts) ~= "table" then
		return nil
	end
	if chat.opts.save_id ~= nil then
		return nil
	end

	local context = chat.buffer_context
	local bufnr = context and context.bufnr
	if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return nil
	end
	if vim.api.nvim_buf_get_name(bufnr) == "" then
		return nil
	end
	if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then
		return nil
	end

	return bufnr
end

local function attach_originating_buffer_to_codecompanion_chat(chat)
	local bufnr = codecompanion_source_buffer_context(chat)
	if not bufnr then
		return
	end

	local ok, editor_context = pcall(require, "codecompanion.interactions.shared.editor_context")
	if not ok or type(editor_context) ~= "table" or type(editor_context.new) ~= "function" then
		return
	end

	local previous_context = _G.codecompanion_current_context
	_G.codecompanion_current_context = bufnr
	local parse_ok, parser = pcall(editor_context.new, "chat")
	if parse_ok and parser and type(parser.parse) == "function" then
		pcall(parser.parse, parser, chat, { content = "#{buffer}" })
	end
	_G.codecompanion_current_context = previous_context
end

local function open_codecompanion_chat_picker(chat)
	require("codecompanion.interactions.chat.action_palette").launch(chat)
end

vim.api.nvim_create_autocmd("User", {
	group = vim.api.nvim_create_augroup("CodeCompanionDefaultBufferContext"),
	pattern = "CodeCompanionChatCreated",
	callback = function(ev)
		local ok, codecompanion = pcall(require, "codecompanion")
		if not ok or type(codecompanion) ~= "table" or type(codecompanion.buf_get_chat) ~= "function" then
			return
		end

		local bufnr = ev.data and ev.data.bufnr
		local chat = codecompanion.buf_get_chat(bufnr)
		attach_originating_buffer_to_codecompanion_chat(chat)
	end,
	desc = "Attach originating file buffer to new CodeCompanion chats",
})

local function ensure_codecompanion(trigger)
	if codecompanion_loaded then
		return true
	end
	local pack_ok = lazy.packadd_all({
		"plenary.nvim",
		"fzf-lua",
		"codecompanion-history.nvim",
		"codecompanion.nvim",
	}, { notify = true, trigger = trigger or "AI keymap" })
	if not pack_ok then
		return false
	end

	local blink_completion_available = ensure_blink_completion(trigger)
	local codecompanion = lazy.require("codecompanion", { notify = true })
	if not codecompanion then
		return false
	end

	local opts = {
		interactions = {
			chat = {
				adapter = {
					name = "copilot",
					model = "gpt-5.6-sol",
				},
				keymaps = {
					-- Deep-merged over CodeCompanion's defaults, which already supply the
					-- keys, `hide = true` for options and the stop callback.
					options = { callback = open_codecompanion_chat_picker, description = "Open chat actions" },
					close = {
						modes = { n = "q" },
						callback = function(chat)
							chat.ui:hide()
						end,
						description = "Hide the chat window",
					},
					stop = { modes = { n = "<C-c>" } },
				},
			},
			inline = {
				adapter = "anthropic",
			},
		},
		extensions = {
			history = {},
		},
	}

	if blink_completion_available then
		opts.interactions.chat.opts = { completion_provider = "blink" }
	end

	codecompanion.setup(opts)

	codecompanion_loaded = true
	return true
end

if not codecompanion_loaded and package.loaded["codecompanion"] == nil then
	vim.api.nvim_create_autocmd("CmdUndefined", {
		group = vim.api.nvim_create_augroup("CodeCompanionCmdLazyLoad"),
		pattern = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionHistory" },
		callback = function(ev)
			ensure_codecompanion(":" .. ev.match)
		end,
		desc = "Load CodeCompanion on first command use",
	})
end

-- Keymaps (eager; callbacks packadd optional plugins before invoking commands)
vim.keymap.set(
	{ "n", "v" },
	"<leader>aa",
	lazy.command(ensure_codecompanion, "CodeCompanionActions", "AI keymap"),
	{ desc = "Action Palette" }
)
vim.keymap.set(
	{ "n", "v" },
	"<leader>ac",
	lazy.command(ensure_codecompanion, "CodeCompanionChat Toggle", "AI keymap"),
	{ desc = "Toggle Chat" }
)
vim.keymap.set(
	"v",
	"<leader>aA",
	lazy.command(ensure_codecompanion, "CodeCompanionChat Add", "AI keymap"),
	{ desc = "Add to Chat" }
)
vim.keymap.set(
	"n",
	"<leader>ah",
	lazy.command(ensure_codecompanion, "CodeCompanionHistory", "AI keymap"),
	{ desc = "Open Chat History" }
)
vim.keymap.set(
	"n",
	"<leader>ai",
	lazy.command(ensure_codecompanion, "CodeCompanion", "AI keymap"),
	{ desc = "Inline Prompt" }
)
vim.keymap.set("v", "<leader>ai", function()
	if not ensure_codecompanion("AI keymap") then
		return
	end
	vim.cmd("'<,'>CodeCompanion")
end, { desc = "Inline Prompt for Selection" })
