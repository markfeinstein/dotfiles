local M = {}

local log = require("mark.log").get("lazy")
local load_triggers = {}

function M.packadd(name, opts)
	opts = opts or {}
	local command_opts = opts.bang and { args = { name }, bang = true } or name
	local ok, err = pcall(vim.cmd.packadd, command_opts)
	if ok then
		load_triggers[name] = load_triggers[name] or opts.trigger or "unknown"
		return true
	end

	local msg = "failed to packadd " .. name
	if opts.log ~= false then
		log.error(msg, err)
	end
	if opts.notify then
		vim.notify(msg, vim.log.levels.ERROR)
	end
	return false, err
end

function M.packadd_all(names, opts)
	for _, name in ipairs(names) do
		local ok, err = M.packadd(name, opts)
		if not ok then
			return false, name, err
		end
	end
	return true
end

-- Only latch successful setup: packadd/require failures and setup errors remain retryable.
-- The optional prerequisite runs before loading the plugin (e.g. Neogit's CodeDiff).
function M.setup_once(plugins, module_name, setup, trigger, before)
	plugins = type(plugins) == "string" and { plugins } or plugins
	local loaded = false
	return function(requested_trigger)
		if loaded then
			return true
		end
		local reason = requested_trigger or trigger
		if before and not before(reason) then
			return false
		end
		if not M.packadd_all(plugins, { notify = true, trigger = reason }) then
			return false
		end
		local mod = M.require(module_name, { notify = true })
		if not mod then
			return false
		end
		setup(mod)
		loaded = true
		return true
	end
end

function M.load_trigger(name)
	return load_triggers[name]
end

function M.command(ensure, command, trigger)
	return function()
		if ensure(trigger) then
			vim.cmd(command)
		end
	end
end

function M.require(name, opts)
	opts = opts or {}
	local ok, mod = pcall(require, name)
	if ok then
		return mod
	end

	local msg = "failed to require " .. name
	if opts.log ~= false then
		log.error(msg, mod)
	end
	if opts.notify then
		vim.notify(msg, vim.log.levels.ERROR)
	end
	return nil, mod
end

return M
