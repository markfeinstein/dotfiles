local M = {}

function M.escape_literal(text)
	return tostring(text or ""):gsub("%%", "%%%%")
end

return M
