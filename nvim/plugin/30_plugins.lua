-- Loading helpers
local misc = require("mini.misc")
_G.now = function(f)
	misc.safely("now", f)
end
_G.later = function(f)
	misc.safely("later", f)
end
_G.now_if_args = #vim.v.argf > 0 and now or later
