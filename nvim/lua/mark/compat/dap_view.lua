local M = {}

-- dap-view has no public non-focusing scopes refresh API. Keep its cache and
-- renderer compatibility isolated here so setting a variable updates Scopes
-- without moving focus into the DAP window.
function M.install_scopes_refresh(dap)
	local function accepted_value(response, arguments)
		if type(response) == "table" and response.value ~= nil then
			return tostring(response.value)
		end
		if type(arguments) == "table" and arguments.value ~= nil then
			return tostring(arguments.value)
		end
		return nil
	end

	local function cache_scope_value(state, value, paths, matches)
		if
			value == nil
			or type(state.variable_path_to_value) ~= "table"
			or type(state.variable_path_to_set_variables) ~= "table"
		then
			return false
		end

		local cached = false
		for path, cached_key in pairs(paths or {}) do
			if matches(path, cached_key) then
				state.variable_path_to_value[path] = value
				state.variable_path_to_set_variables[path] = true
				cached = true
			end
		end
		return cached
	end

	local function cache_set_variable(state, arguments, value)
		if type(arguments) ~= "table" or arguments.name == nil or arguments.variablesReference == nil then
			return nil
		end

		local name = tostring(arguments.name)
		local variables_reference = arguments.variablesReference
		return cache_scope_value(state, value, state.variable_path_to_name, function(path, variable_name)
			return variable_name == name
				and (state.variable_path_to_parent_reference or {})[path] == variables_reference
		end)
	end

	local function cache_set_expression(state, arguments, value)
		if type(arguments) ~= "table" or arguments.expression == nil then
			return nil
		end

		local expression = tostring(arguments.expression)
		return cache_scope_value(state, value, state.variable_path_to_evaluate_name, function(_, evaluate_name)
			return evaluate_name == expression
		end)
	end

	local function refresh_after_set(cache_write)
		return function(_, err, response, arguments)
			if err or type(arguments) ~= "table" then
				return
			end

			local value = accepted_value(response, arguments)
			if value == nil then
				return
			end

			local state = require("dap-view.state")
			if cache_write(state, arguments, value) == nil or state.current_section ~= "scopes" then
				return
			end

			coroutine.wrap(function()
				require("dap-view.views").switch_to_view("scopes")
			end)()
		end
	end

	dap.listeners.after.setVariable.dotfiles_dap_view_scopes_refresh = refresh_after_set(cache_set_variable)
	dap.listeners.after.setExpression.dotfiles_dap_view_scopes_refresh = refresh_after_set(cache_set_expression)
end

return M
