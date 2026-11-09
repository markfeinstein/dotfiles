local M = {}

M.default_palette = {
	green = "#88aa88",
	pink = "#dd8888",
	teal = "#88cccc",
	purple = "#bb88cc",
	orange = "#ddaa77",
	red = "#cc8888",
	muted = "#6e6a86",
	subtle = "#8e8a9a",
	annotation = "#a4a0bc",
	text = "#e0def4",
	highlight_low = "#21202e",
	highlight_med = "#403d52",
	highlight_high = "#524f67",
	base = "NONE",
	surface = "#3a3a3a",
	overlay = "#2a2a3a",
}

local function render(name, palette)
	local p = vim.tbl_extend("force", M.default_palette, palette or {})
	-- Only clear highlights if switching from another colorscheme
	if vim.g.colors_name then
		vim.cmd("highlight clear")
	end

	-- Cache API function for performance
	local hl = vim.api.nvim_set_hl

	-- Essential editor highlights
	hl(0, "Title", { fg = p.teal, bold = true })
	hl(0, "Special", { fg = p.purple })
	hl(0, "NonText", { link = "Dimmed" })
	hl(0, "Normal", { fg = p.text, bg = p.base })
	hl(0, "NormalFloat", { link = "Normal" })
	hl(0, "NormalNC", { link = "Normal" })
	hl(0, "Cursor", { fg = p.base, bg = p.text })
	hl(0, "CursorLine", { bg = p.highlight_low })
	-- The statusline updates the foreground to the active mode color.
	hl(0, "CursorLineNr", { fg = p.green, bg = p.highlight_low })
	-- Keep gutter text out of the shared Dimmed group. Terminal contrast
	-- correction can promote dimmed low-contrast colors to white.
	hl(0, "LineNr", { fg = p.muted })
	hl(0, "SignColumn", { fg = p.muted, bg = p.base })
	hl(0, "CursorLineSign", { bg = p.highlight_low })
	hl(0, "CursorLineFold", { bg = p.highlight_low })
	hl(0, "Visual", { bg = p.highlight_med })
	hl(0, "Search", { fg = p.search_fg or p.base, bg = p.search_bg or p.orange })
	hl(0, "IncSearch", { fg = p.inc_search_fg or p.base, bg = p.inc_search_bg or p.red })
	hl(0, "CurSearch", { link = "IncSearch" })

	-- Git diff highlights (Neovim 0.12+ core, used by MiniDiff and statuscolumn)
	hl(0, "GitStatusAdded", { fg = p.green })
	hl(0, "GitStatusChanged", { fg = p.red })
	hl(0, "GitStatusRemoved", { fg = p.pink })
	hl(0, "Added", { fg = p.green })
	hl(0, "Changed", { fg = p.orange })
	hl(0, "Removed", { fg = p.pink })
	hl(0, "DiffAdd", { fg = p.green, bg = p.highlight_low })
	hl(0, "DiffChange", { fg = p.orange, bg = p.highlight_low })
	hl(0, "DiffDelete", { fg = p.pink, bg = p.highlight_low })
	hl(0, "DiffText", { fg = p.text, bg = p.highlight_med })

	-- MiniDiff signs use the same palette as the statusline Git summary.
	hl(0, "MiniDiffSignAdd", { link = "GitStatusAdded" })
	hl(0, "MiniDiffSignChange", { link = "GitStatusChanged" })
	hl(0, "MiniDiffSignDelete", { link = "GitStatusRemoved" })
	hl(0, "MiniDiffOverAdd", { link = "DiffAdd" })
	hl(0, "MiniDiffOverChange", { link = "DiffText" })
	hl(0, "MiniDiffOverDelete", { link = "DiffDelete" })

	-- Status line (immediately visible)
	hl(0, "StatusLine", { fg = p.muted, bold = true })
	hl(0, "StatusLineNC", { fg = p.muted })
	hl(0, "StatusLineNormal", { fg = p.green, bold = true })
	hl(0, "StatusLineInsert", { fg = p.pink, bold = true })
	hl(0, "StatusLineVisual", { fg = p.red, bold = true })
	hl(0, "StatusLineCommand", { fg = p.orange, bold = true })
	hl(0, "StatusLineReplace", { fg = p.purple, bold = true })
	hl(0, "StatusLineTerminal", { fg = p.teal, bold = true })
	hl(0, "StatusLineRemote", { fg = p.green, bold = true })
	if p.statusline_mode_fg then
		hl(0, "StatusLineModeText", { fg = p.statusline_mode_fg, bold = true })
	end
	hl(0, "StatusLineModifiedBuffer", { fg = p.pink, bold = true })
	hl(0, "StatusLineDebug", { fg = p.pink, bold = true })
	hl(0, "StatusLineMotion", { fg = p.red, bold = true })
	local percentage_bg = p.statusline_percentage_bg or p.teal
	local position_bg = p.statusline_position_bg or p.green
	hl(0, "StatusLineBufferPercentage", {
		fg = p.statusline_chip_fg or p.surface,
		bg = percentage_bg,
		bold = true,
	})
	hl(0, "StatusLineBufferPercentageSymbol", { fg = percentage_bg, bold = true })
	hl(0, "StatusLineBufferPosition", {
		fg = p.statusline_chip_fg or p.surface,
		bg = position_bg,
		bold = true,
	})
	hl(0, "StatusLineBufferPositionSymbol", { fg = position_bg, bold = true })

	-- Statusline breadcrumbs (0.12+ moved from winbar)
	hl(0, "StatusLineBreadcrumbPath", { fg = p.teal })
	hl(0, "StatusLineBreadcrumbSeparator", { fg = p.muted })
	hl(0, "StatusLineBreadcrumbSymbol", { fg = p.purple })

	-- Popup menu (completion visible immediately in insert mode)
	hl(0, "Pmenu", { fg = p.subtle })
	hl(0, "PmenuSel", { fg = p.text, bg = p.overlay })
	hl(0, "PmenuSbar", { bg = p.overlay })
	hl(0, "PmenuThumb", { bg = p.highlight_high })
	hl(0, "PmenuBorder", { fg = p.highlight_high })

	-- Additional editor highlights
	hl(0, "CursorColumn", { bg = p.highlight_low })
	hl(0, "Folded", { fg = p.purple, dim = true, italic = true })
	hl(0, "ColorColumn", { bg = p.highlight_low })
	hl(0, "WinSeparator", { fg = p.highlight_med })
	hl(0, "TabLine", { fg = p.subtle, bg = p.surface })
	hl(0, "TabLineFill", { bg = p.base })
	hl(0, "TabLineSel", { fg = p.text })
	hl(0, "MatchParen", { fg = p.text, bg = p.highlight_med, bold = true })
	hl(0, "Question", { fg = p.orange })
	hl(0, "ModeMsg", { fg = p.teal, bold = true })
	hl(0, "MoreMsg", { fg = p.teal, bold = true })
	hl(0, "ErrorMsg", { fg = p.pink, bold = true })
	hl(0, "WarningMsg", { fg = p.orange, bold = true })
	hl(0, "Conceal", { fg = p.muted, conceal = true, dim = true })
	hl(0, "SpecialKey", { fg = p.teal, dim = true })
	hl(0, "Whitespace", { fg = p.highlight_med, dim = true })
	hl(0, "Directory", { fg = p.teal })
	hl(0, "QuickFixLine", { bg = p.overlay })

	-- Syntax highlights
	hl(0, "Comment", { fg = p.muted, italic = true })
	hl(0, "Dimmed", { fg = p.muted, dim = true })
	hl(0, "Constant", { fg = p.orange })
	hl(0, "String", { link = "Constant" })
	hl(0, "Boolean", { fg = p.red })
	hl(0, "Identifier", { fg = p.red })
	hl(0, "Function", { fg = p.pink })
	hl(0, "Statement", { link = "Keyword" })
	hl(0, "Label", { link = "Type" })
	hl(0, "Operator", { fg = p.subtle })
	hl(0, "Keyword", { fg = p.green })
	hl(0, "PreProc", { link = "Special" })
	hl(0, "Type", { fg = p.teal })
	hl(0, "SpecialChar", { link = "Identifier" })
	hl(0, "Tag", { link = "Type" })
	hl(0, "Delimiter", { link = "Operator" })
	hl(0, "SpecialComment", { fg = p.purple, italic = true, dim = true })
	hl(0, "Debug", { fg = p.pink, dim = true })
	hl(0, "Ignore", { fg = p.muted, dim = true })
	hl(0, "Error", { fg = p.pink, bold = true })
	hl(0, "Todo", { fg = p.purple, bg = p.surface, bold = true })

	-- Diff (additional highlights)
	hl(0, "DiffTextAdd", { fg = p.diff_text_add_fg or p.text, bg = p.diff_text_add_bg or p.green })
	hl(0, "diffAdded", { link = "Added" })
	hl(0, "diffRemoved", { link = "Removed" })
	hl(0, "diffChanged", { link = "Changed" })
	hl(0, "diffFile", { link = "Type" })
	hl(0, "diffNewFile", { link = "Added" })
	hl(0, "diffOldFile", { link = "Removed" })
	hl(0, "diffLine", { link = "Special" })

	-- Spell checking
	hl(0, "SpellBad", { sp = p.pink, undercurl = true })
	hl(0, "SpellCap", { sp = p.orange, undercurl = true })
	hl(0, "SpellLocal", { sp = p.teal, undercurl = true })
	hl(0, "SpellRare", { sp = p.purple, undercurl = true })

	-- LSP diagnostics
	hl(0, "DiagnosticError", { link = "Function" })
	hl(0, "DiagnosticWarn", { link = "Constant" })
	hl(0, "DiagnosticInfo", { link = "Type" })
	hl(0, "DiagnosticHint", { link = "Special" })
	hl(0, "DiagnosticOk", { link = "Keyword" })
	hl(0, "DiagnosticUnderlineError", { sp = p.pink, undercurl = true })
	hl(0, "DiagnosticUnderlineWarn", { sp = p.orange, undercurl = true })
	hl(0, "DiagnosticUnderlineInfo", { sp = p.teal, undercurl = true })
	hl(0, "DiagnosticUnderlineHint", { sp = p.purple, undercurl = true })
	hl(0, "DiagnosticUnderlineOk", { sp = p.green, undercurl = true })
	hl(0, "DiagnosticVirtualTextError", { fg = p.pink, bg = p.highlight_low, dim = true })
	hl(0, "DiagnosticVirtualTextWarn", { fg = p.orange, bg = p.highlight_low, dim = true })
	hl(0, "DiagnosticVirtualTextInfo", { fg = p.teal, bg = p.highlight_low, dim = true })
	hl(0, "DiagnosticVirtualTextHint", { fg = p.purple, bg = p.highlight_low, dim = true })
	hl(0, "DiagnosticVirtualTextOk", { fg = p.green, bg = p.highlight_low, dim = true })

	-- LSP Semantic Tokens
	hl(0, "LspReferenceTarget", {
		fg = p.reference_target_fg or p.base,
		bg = p.reference_target_bg or p.orange,
		bold = true,
	})
	hl(0, "LspSignatureActiveParameter", { fg = p.orange, bold = true })
	hl(0, "LspCodeLens", { fg = p.purple, bold = true, italic = true, dim = true })
	hl(0, "LspInlayHint", { fg = p.annotation, bg = p.highlight_low, italic = true, dim = true })

	-- Treesitter
	hl(0, "@variable", { link = "Normal" })
	hl(0, "@variable.builtin", { link = "Function" })
	hl(0, "@variable.parameter", { fg = p.purple, italic = true })
	hl(0, "@variable.member", { link = "Type" })
	hl(0, "@annotation", { fg = p.purple, dim = true, italic = true })
	hl(0, "@attribute", { fg = p.purple, dim = true, italic = true })
	hl(0, "@error", { link = "Function" })
	hl(0, "@function.macro", { link = "Special" })
	hl(0, "@constructor", { link = "Type" })
	hl(0, "@keyword.import", { link = "Special" })
	hl(0, "@type.qualifier", { link = "Keyword" })
	hl(0, "@punctuation.special", { link = "Identifier" })
	hl(0, "@comment.error", { fg = p.pink, dim = true })
	hl(0, "@comment.warning", { fg = p.orange, dim = true })
	hl(0, "@comment.note", { fg = p.teal, dim = true })
	hl(0, "@comment.todo", { fg = p.purple, bold = true })
	hl(0, "@markup.link", { link = "Type" })
	hl(0, "@markup.link.url", { fg = p.purple, underline = true })
	hl(0, "@markup.raw", { link = "Constant" })
	hl(0, "@markup.quote", { fg = p.subtle, dim = true, italic = true })
	hl(0, "@markup.list", { link = "Identifier" })
	hl(0, "@markup.list.checked", { link = "Keyword" })
	hl(0, "@markup.list.unchecked", { fg = p.muted, dim = true })
	hl(0, "@tag.attribute", { link = "Special" })

	-- Markdown
	hl(0, "markdownHeadingDelimiter", { link = "markdownH1" })
	hl(0, "markdownH1", { fg = p.teal, bold = true })
	hl(0, "markdownH2", { link = "markdownH1" })
	hl(0, "markdownH3", { link = "markdownH1" })
	hl(0, "markdownH4", { link = "markdownH1" })
	hl(0, "markdownH5", { link = "markdownH1" })
	hl(0, "markdownH6", { link = "markdownH1" })
	hl(0, "markdownLinkText", { link = "Type" })
	hl(0, "markdownUrl", { fg = p.purple, underline = true })
	hl(0, "markdownCode", { link = "Constant" })
	hl(0, "markdownCodeBlock", { link = "Constant" })
	hl(0, "markdownCodeDelimiter", { link = "Identifier" })
	hl(0, "markdownBold", { bold = true })
	hl(0, "markdownItalic", { italic = true })

	-- vim._core.ui2 (replaces noice.nvim) — needed immediately
	hl(0, "CmdPopup", { bg = "NONE", fg = "NONE" })
	hl(0, "DialogPopup", { link = "NormalFloat" })
	hl(0, "MsgPopup", { link = "NormalFloat" })
	hl(0, "PagerPopup", { link = "NormalFloat" })

	-- Plugin-specific highlight groups.
	-- Applied during colorscheme load and re-applied on ColorScheme change so runtime :colorscheme works.
	local function apply_debug_virtual_text_highlights()
		-- nvim-dap-virtual-text defaults to Comment, which terminal contrast
		-- correction can promote to Normal-looking text when colors are too dim.
		-- Use the neutral annotation foreground so routine values recede without
		-- relying on dim; changed values and errors keep their semantic accents below.
		-- Inline values remain distinct from code through brackets plus italics.
		hl(0, "NvimDapVirtualText", { fg = p.annotation, italic = true })
		hl(0, "NvimDapVirtualTextChanged", { fg = p.orange, italic = true })
		hl(0, "NvimDapVirtualTextError", { fg = p.pink, bold = true })
		hl(0, "NvimDapVirtualTextInfo", { fg = p.purple, italic = true })
		-- nvim-dap-view's lazy-loaded highlighter uses update=true to add dim to
		-- virtual text groups, so mark.dap calls this again after dap-view setup.
		hl(0, "NvimDapViewVirtualText", { fg = p.teal, italic = true })
		hl(0, "NvimDapViewVirtualTextUpdated", { fg = p.orange, italic = true })
		hl(0, "NvimDapViewBooleanDim", { fg = p.red, italic = true })
		hl(0, "NvimDapViewStringDim", { fg = p.teal, italic = true })
		hl(0, "NvimDapViewNumberDim", { fg = p.orange, italic = true })
		hl(0, "NvimDapViewFloatDim", { fg = p.orange, italic = true })
		hl(0, "NvimDapViewFunctionDim", { fg = p.pink, italic = true })
		hl(0, "NvimDapViewConstantDim", { fg = p.purple, italic = true })
	end

	local function apply_dap_view_winbar_highlights()
		-- Winbar sections render as a pill per view, matching the statusline mode
		-- indicator: accent chip for the selected view, faint slab for the rest. Teal
		-- matches DapStopped and the statusline position chips; pink stays reserved
		-- for errors and breakpoints.
		hl(0, "NvimDapViewTab", { fg = p.subtle, bg = p.highlight_low })
		hl(0, "NvimDapViewTabSeparator", { fg = p.highlight_low, bg = "NONE" })
		hl(0, "NvimDapViewTabSelected", { fg = p.highlight_low, bg = p.teal, bold = true })
		hl(0, "NvimDapViewTabSelectedSeparator", { fg = p.teal, bg = "NONE" })
		hl(0, "NvimDapViewTabFill", { bg = "NONE" })
	end

	_G._apply_dap_view_winbar_highlights = apply_dap_view_winbar_highlights

	_G._apply_debug_virtual_text_highlights = apply_debug_virtual_text_highlights

	local function apply_plugin_highlights()
		-- WhichKey
		hl(0, "WhichKey", { link = "Special" })
		hl(0, "WhichKeyGroup", { link = "Type" })
		hl(0, "WhichKeyDesc", { link = "Normal" })
		hl(0, "WhichKeySeparator", { fg = p.muted })
		hl(0, "WhichKeyBorder", { fg = p.highlight_high })
		-- Mini
		hl(0, "MiniSurround", { fg = p.base, bg = p.red })
		-- mini.icons default links are intentionally broad and leave MiniIconsGrey
		-- empty. Define the fixed icon palette here so file/LSP icons never fall
		-- back to Normal text after startup or a colorscheme reload.
		hl(0, "MiniIconsAzure", { fg = p.teal })
		hl(0, "MiniIconsBlue", { fg = p.teal })
		hl(0, "MiniIconsCyan", { fg = p.teal })
		hl(0, "MiniIconsGreen", { fg = p.green })
		hl(0, "MiniIconsGrey", { fg = p.subtle })
		hl(0, "MiniIconsOrange", { fg = p.orange })
		hl(0, "MiniIconsPurple", { fg = p.purple })
		hl(0, "MiniIconsRed", { fg = p.pink })
		hl(0, "MiniIconsYellow", { fg = p.orange })
		-- Flash
		hl(0, "FlashLabel", { fg = p.base, bg = p.red, bold = true })
		hl(0, "FlashBackdrop", { fg = p.muted, dim = true })
		hl(0, "FlashMatch", { fg = p.teal, bold = true })
		hl(0, "FlashCurrent", { fg = p.orange, bold = true })
		-- DAP
		hl(0, "DapBreakpoint", { fg = p.red, bold = true })
		hl(0, "DapBreakpointCondition", { link = "DiagnosticWarn" })
		hl(0, "DapStopped", { fg = p.teal, bold = true })
		hl(0, "DapStoppedLine", { link = "Visual" })
		apply_debug_virtual_text_highlights()
		apply_dap_view_winbar_highlights()
		-- Neotest
		hl(0, "NeotestAdapterName", { fg = p.purple, bold = true })
		hl(0, "NeotestBorder", { fg = p.highlight_high })
		hl(0, "NeotestDir", { link = "Type" })
		hl(0, "NeotestExpandMarker", { link = "Operator" })
		hl(0, "NeotestFailed", { fg = p.pink, bold = true })
		hl(0, "NeotestFile", { link = "Type" })
		hl(0, "NeotestFocused", { fg = p.text, bg = p.highlight_med, bold = true })
		hl(0, "NeotestIndent", { fg = p.highlight_med })
		hl(0, "NeotestMarked", { fg = p.red, bg = p.highlight_low, bold = true })
		hl(0, "NeotestNamespace", { link = "Type" })
		hl(0, "NeotestPassed", { fg = p.green, bold = true })
		hl(0, "NeotestRunning", { fg = p.orange, bold = true })
		hl(0, "NeotestWinSelect", { fg = p.purple, bg = p.highlight_med, bold = true })
		hl(0, "NeotestSkipped", { fg = p.muted, dim = true })
		hl(0, "NeotestTarget", { link = "Identifier" })
		hl(0, "NeotestTest", { link = "Normal" })
		hl(0, "NeotestUnknown", { fg = p.muted, dim = true })
		hl(0, "NeotestWatching", { link = "Special" })
		-- Trouble
		hl(0, "TroubleIconDirectory", { link = "MiniIconsAzure" })
		hl(0, "TroubleIconFile", { link = "MiniIconsBlue" })
		hl(0, "TroubleIconVariable", { link = "MiniIconsCyan" })
	end

	apply_plugin_highlights()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("base_colorscheme_plugin_highlights"),
		callback = apply_plugin_highlights,
	})

	-- Shell output messages (Neovim 0.12+)
	hl(0, "OkMsg", { fg = p.green, bold = true })
	hl(0, "StdoutMsg", { link = "Type" })
	hl(0, "StderrMsg", { link = "Function" })

	-- Set terminal colors
	local terminal_palette = {
		"overlay",
		"pink",
		"green",
		"orange",
		"teal",
		"purple",
		"red",
		"text",
		"muted",
		"pink",
		"green",
		"orange",
		"teal",
		"purple",
		"red",
		"text",
	}
	for index, key in ipairs(terminal_palette) do
		vim.g["terminal_color_" .. (index - 1)] = p[key]
	end
	vim.g.colors_name = name
end

function M.apply(name, palette)
	local ok, err = pcall(render, name or "base", palette)
	if not ok then
		vim.notify(
			("%s: failed to load base colorscheme: %s"):format(name or "base", tostring(err)),
			vim.log.levels.ERROR
		)
	end
	return ok, err
end

return M
