local M = {}

local function is_closing(handle)
	return handle and type(handle.is_closing) == "function" and handle:is_closing()
end

---Stop and close a vim.defer_fn/libuv timer handle.
---
---vim.defer_fn returns a libuv timer. Calling stop() prevents future callbacks,
---but the handle remains allocated until close(); canceled debounces should do
---both. close() is intentionally protected because callbacks may race with
---manual cleanup during shutdown.
---@param handle uv.uv_timer_t?
---@return nil
function M.cancel(handle)
	if not handle then
		return nil
	end
	pcall(handle.stop, handle)
	if type(handle.close) == "function" and not is_closing(handle) then
		pcall(handle.close, handle)
	end
	return nil
end

---Cancel the timer stored in owner[key] and clear the slot.
---@param owner table
---@param key any
function M.cancel_slot(owner, key)
	if not owner then
		return
	end
	local handle = owner[key]
	owner[key] = nil
	M.cancel(handle)
end

---Replace owner[key] with a one-shot deferred callback.
---
---The callback only clears owner[key] when it is still the timer that fired, so
---a stale callback cannot erase a newer replacement scheduled in the same slot.
---@param owner table
---@param key any
---@param delay_ms integer
---@param callback function
---@return uv.uv_timer_t
function M.replace(owner, key, delay_ms, callback)
	M.cancel_slot(owner, key)
	local handle
	handle = vim.defer_fn(function()
		if owner[key] ~= handle then
			return
		end
		owner[key] = nil
		callback()
	end, delay_ms)
	owner[key] = handle
	return handle
end

return M
