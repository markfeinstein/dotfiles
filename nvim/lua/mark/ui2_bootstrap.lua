local M = {}

local function set_cmdheight(value)
	vim.opt.cmdheight = value
end

function M.probe(opts)
	opts = opts or {}
	local disabled = opts.disabled
	if disabled == nil then
		disabled = vim.g.ui2_disabled == 1 or vim.env.NVIM_DISABLE_UI2 == "1"
	end
	if disabled then
		local update_cmdheight = opts.set_cmdheight or set_cmdheight
		update_cmdheight(1)
		return nil, "disabled"
	end

	local require_ui2 = opts.require_ui2 or require
	local ok, ui2 = pcall(require_ui2, "vim._core.ui2")
	if not ok or type(ui2) ~= "table" then
		local update_cmdheight = opts.set_cmdheight or set_cmdheight
		local notify = opts.notify or vim.notify
		update_cmdheight(1)
		notify("vim._core.ui2 is unavailable; falling back to native command-line UI", vim.log.levels.WARN)
		return nil, "unavailable", ui2
	end
	return ui2, "available"
end

function M.enable(ui2, config, opts)
	opts = opts or {}
	local update_cmdheight = opts.set_cmdheight or set_cmdheight
	update_cmdheight(0)
	local ok, err = pcall(ui2.enable, config)
	if ok then
		return true
	end

	if opts.log then
		opts.log.error("UI2 initialization failed", err)
	end
	local notify = opts.notify or vim.notify
	update_cmdheight(1)
	notify(
		"UI2 initialization failed: " .. tostring(err) .. "\nFalling back to the native command-line UI.",
		vim.log.levels.WARN
	)
	return false, err
end

return M
