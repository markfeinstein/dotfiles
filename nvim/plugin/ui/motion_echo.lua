local timer = require("mark.timer")

_G._motion_echo = _G._motion_echo or {}

-- Key echo state for normal/visual/operator-pending mode
local key_echo_state = {
	pending_count = "", -- Explicit count being built (e.g., "4")
	sequence = "", -- Current key sequence (e.g., "viw", "dw")
	last_key = "", -- Last key pressed (for repeat detection)
	repeat_count = 0, -- Number of times same key was repeated
	display = "",
	normal_prefix_pending = false, -- True when [ or ] is waiting for second key
}

-- showcmdloc=statusline keeps native showcmd out of UI2, and the statusline
-- has no %S, so this key echo is the only pending-command display.
local function motion_echo()
	return key_echo_state.display
end

local function reset_key_echo(clear_display)
	key_echo_state.pending_count = ""
	key_echo_state.sequence = ""
	key_echo_state.last_key = ""
	key_echo_state.repeat_count = 0
	key_echo_state.normal_prefix_pending = false
	if clear_display then
		key_echo_state.display = ""
	end
end

-- Track keys for motion echo
-- Debounced redrawstatus to avoid excessive redraws during rapid input
local _redraw_timer = {}
local function debounced_redraw()
	if _redraw_timer.handle then
		return
	end
	timer.replace(_redraw_timer, "handle", 50, function()
		pcall(vim.cmd.redrawstatus)
	end)
end

vim.schedule(function()
	vim.on_key(function(key, typed)
		-- Ignore synthesized keys (typed is empty for internal/post-mapping keys)
		-- This prevents duplicate sequences like viw -> viwiw
		if typed == "" then
			return
		end

		local mode = vim.api.nvim_get_mode().mode

		-- Track in normal, visual, and operator-pending modes
		if mode == "i" or not (mode == "n" or mode:match("^no") or mode:match("^[vV\22]")) then
			-- Clear on mode change to other modes
			reset_key_echo(true)
			return
		end

		-- Decode key (use typed key, not post-mapping key)
		local decoded = vim.fn.keytrans(typed)

		-- Skip special keys except Space and Esc
		if decoded:match("^<.*>$") and decoded ~= "<Space>" and decoded ~= "<Esc>" then
			return
		end

		-- Esc clears everything
		if decoded == "<Esc>" then
			reset_key_echo(true)
			debounced_redraw()
			return
		end

		-- Handle digits (count building)
		-- Note: 0 is only a count digit if count already started, otherwise it's a motion
		if decoded:match("^[1-9]$") or (decoded == "0" and key_echo_state.pending_count ~= "") then
			key_echo_state.pending_count = key_echo_state.pending_count .. decoded
			key_echo_state.display = key_echo_state.pending_count
			key_echo_state.sequence = ""
			key_echo_state.last_key = ""
			key_echo_state.repeat_count = 0
			key_echo_state.normal_prefix_pending = false
			debounced_redraw()
			return
		end

		-- Handle motion keys (h/j/k/l/space/{/}) with special repeat compression
		if
			decoded == "h"
			or decoded == "j"
			or decoded == "k"
			or decoded == "l"
			or decoded == "<Space>"
			or decoded == "{"
			or decoded == "}"
		then
			local motion = decoded == "<Space>" and " " or decoded

			-- If same motion as last, increment repeat count. Explicit counts
			-- dominate repeat compression and reset the repeat chain below.
			if
				key_echo_state.pending_count == ""
				and motion == key_echo_state.last_key
				and key_echo_state.sequence == ""
			then
				key_echo_state.repeat_count = key_echo_state.repeat_count + 1
				-- Format: jjjjj -> 4jj (count shows repeats beyond first 2)
				if key_echo_state.repeat_count == 2 then
					key_echo_state.display = motion .. motion
				else
					-- 3rd repeat onwards: show as (count-1)jj
					key_echo_state.display = tostring(key_echo_state.repeat_count - 1) .. motion .. motion
				end
			else
				-- New motion or explicit count: reset repeat chain and show count + motion (e.g., 4j)
				key_echo_state.display = key_echo_state.pending_count .. motion
				key_echo_state.sequence = ""
				key_echo_state.last_key = motion
				key_echo_state.repeat_count = 1
				key_echo_state.pending_count = ""
				key_echo_state.normal_prefix_pending = false
			end

			debounced_redraw()
			return
		end

		-- Handle other printable keys (operators, text objects, etc.)
		-- Build sequence: d -> dw, v -> vi -> viw
		if decoded:match("^[a-zA-Z]$") or decoded:match("^[%p]$") then
			-- In normal mode, check if we should append or start new sequence
			if mode == "n" then
				-- If normal_prefix_pending, append once then clear pending
				if key_echo_state.normal_prefix_pending then
					key_echo_state.sequence = key_echo_state.sequence .. decoded
					key_echo_state.display = key_echo_state.pending_count .. key_echo_state.sequence
					key_echo_state.normal_prefix_pending = false
				else
					-- Start new sequence (overwrite previous command)
					key_echo_state.sequence = decoded
					key_echo_state.display = key_echo_state.pending_count .. key_echo_state.sequence
					-- Set pending if this is [ or ]
					if decoded == "[" or decoded == "]" then
						key_echo_state.normal_prefix_pending = true
					end
				end
			else
				-- In visual/operator-pending mode, always append (viw, dw, etc.)
				key_echo_state.sequence = key_echo_state.sequence .. decoded
				key_echo_state.display = key_echo_state.pending_count .. key_echo_state.sequence
			end

			key_echo_state.last_key = decoded
			key_echo_state.repeat_count = 0
			key_echo_state.pending_count = ""
			debounced_redraw()
			return
		end

		-- Other keys: clear state but leave display
		reset_key_echo(false)
	end, vim.api.nvim_create_namespace("statusline_key_echo"))
end)

_G._motion_echo.get = motion_echo
