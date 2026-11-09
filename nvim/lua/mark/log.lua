local M = {}

local loggers = {}

local function normalize_name(name)
	if name == nil or name == "" then
		return "mark.nvim"
	end
	if name:match("^mark%.nvim") then
		return name
	end
	return "mark.nvim." .. name
end

function M.get(name, level)
	name = normalize_name(name)
	loggers[name] = loggers[name] or vim.log.new({ name = name, level = level })
	return loggers[name]
end

return M
