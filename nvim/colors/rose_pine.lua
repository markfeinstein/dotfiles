-- Rosé Pine colorscheme for Neovim.
-- Color values come from the repository-wide canonical palette.

-- Neovim's TUI detects the terminal background with OSC 11 before loading
-- user config and follows runtime theme notifications. Do not set 'background'
-- here: doing so marks it as a user override and disables that synchronization.
local dark_variant = vim.env.DOTFILES_ROSE_PINE_DARK_VARIANT
if dark_variant ~= "rose-pine" and dark_variant ~= "rose-pine-moon" then
	dark_variant = "rose-pine"
end

local light = vim.o.background == "light"
local variant = light and "rose-pine-dawn" or dark_variant
local theme = require("mark.palette").variant(variant)
local p = theme.colors
local derived = theme.derived

require("mark.colors").apply("rose_pine", {
	green = p.pine,
	pink = p.love,
	teal = p.foam,
	purple = p.iris,
	orange = p.gold,
	red = p.rose,
	muted = p.muted,
	subtle = p.subtle,
	annotation = derived.annotation or p.subtle,
	text = p.text,
	highlight_low = p.highlightLow,
	highlight_med = p.highlightMed,
	highlight_high = p.highlightHigh,
	surface = p.surface,
	overlay = p.overlay,
	search_fg = light and p.text or p.base,
	search_bg = light and p.highlightMed or p.gold,
	inc_search_fg = light and p.text or p.base,
	inc_search_bg = light and p.highlightHigh or p.rose,
	diff_text_add_fg = light and p.text or p.text,
	diff_text_add_bg = light and p.highlightMed or p.pine,
	statusline_chip_fg = light and p.text or p.surface,
	statusline_mode_fg = p.base,
	statusline_percentage_bg = light and p.highlightMed or p.foam,
	statusline_position_bg = light and p.highlightMed or p.pine,
	reference_target_fg = light and p.text or p.base,
	reference_target_bg = light and p.highlightMed or p.gold,
})
