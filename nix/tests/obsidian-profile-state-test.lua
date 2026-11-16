local function assert_equal(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local profile = vim.g.dotfiles_obsidian or {}
local state = assert(vim.env.DOTFILES_OBSIDIAN_EXPECT_STATE, "DOTFILES_OBSIDIAN_EXPECT_STATE is required")
local commands = vim.api.nvim_get_commands({})
local has_workspaces = #(profile.workspaces or {}) > 0

if state == "disabled" then
	assert(has_workspaces, "disabled test profile should retain its configured workspace")
	assert_equal((profile.capture or {}).enabled, false, "capture flag")
	assert_equal((profile.references or {}).enabled, false, "references flag")
elseif state == "no-workspace" then
	assert(not has_workspaces, "no-workspace test profile should have no workspaces")
	assert_equal((profile.capture or {}).enabled, true, "capture flag")
	assert_equal((profile.references or {}).enabled, true, "references flag")
else
	error("unknown expected state: " .. state)
end

for _, name in ipairs({ "ObsidianQuestion", "ObsidianAnswer", "ObsidianLog" }) do
	assert(commands[name] == nil, name .. " must not be registered")
end
for _, lhs in ipairs({ "<leader>mq", "<leader>ma", "<leader>ml" }) do
	assert(vim.fn.maparg(lhs, "n") == "", lhs .. " must not be mapped")
end
assert(_G._dotfiles_obsidian_refs_register == nil, "reference registration must stay disabled")

print("PASS: Obsidian capture entry points remain inactive for " .. state)
vim.cmd("qa!")
