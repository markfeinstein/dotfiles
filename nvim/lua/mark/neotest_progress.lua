local M = {}

local pending_runs = {}
local pending_run_ttl_ms = 1000

---@param tree neotest.Tree?
---@return string? root_id, table<string, true> ids, integer count
local function tree_run_ids(tree)
	if not tree then
		return nil, {}, 0
	end
	local ids = {}
	for _, node in tree:iter_nodes() do
		ids[node:data().id] = true
	end
	return tree:data().id, ids, vim.tbl_count(ids)
end

function M.track(tree, suppress_notification)
	-- Track every invocation because run listeners are deferred. Otherwise an
	-- older same-position event can consume a later DAP suppression marker.
	local root_id, ids, id_count = tree_run_ids(tree)
	if root_id ~= nil and id_count > 0 then
		pending_runs[#pending_runs + 1] = {
			created_at = vim.uv.now(),
			id_count = id_count,
			ids = ids,
			root_id = root_id,
			suppress_notification = suppress_notification,
		}
	end
end

function M.consumer(client)
	local state = { runs = {}, next_seq = 0 }

	local function active_count(visible_only)
		local count = 0
		for _, run in pairs(state.runs) do
			if run.active and (not visible_only or not run.suppress_notification) then
				count = count + 1
			end
		end
		return count
	end

	local function status_key(status)
		status = status and tostring(status):lower() or ""
		return (status == "passed" or status == "failed" or status == "skipped") and status or nil
	end

	local function counts()
		local total = 0
		local passed, failed, skipped = 0, 0, 0
		for _, run in pairs(state.runs) do
			if not run.suppress_notification then
				total = total + run.total
				for _, result in pairs(run.results) do
					local key = status_key(result.status)
					if key == "passed" then
						passed = passed + 1
					elseif key == "failed" then
						failed = failed + 1
					elseif key == "skipped" then
						skipped = skipped + 1
					end
				end
			end
		end
		return total, passed + failed + skipped, passed, failed, skipped
	end

	local function has_visible_runs(failed_only)
		for _, run in pairs(state.runs) do
			if not run.suppress_notification and (not failed_only or run.terminal_failed) then
				return true
			end
		end
		return false
	end

	local function prune_finished_visible_runs()
		for seq, run in pairs(state.runs) do
			if not run.active and not run.suppress_notification then
				state.runs[seq] = nil
			end
		end
	end

	local function progress_text(final)
		local total, completed, passed, failed, skipped = counts()
		local prefix = final and "Neotest complete" or "Neotest running"
		return string.format(
			"%s: %d/%d completed — %d passed, %d failed, %d skipped",
			prefix,
			completed,
			total,
			passed,
			failed,
			skipped
		)
	end

	local function emit_progress(text, status, percent)
		pcall(vim.api.nvim_echo, { { text } }, status ~= "running", {
			kind = "progress",
			id = "mark.neotest",
			source = "Neotest",
			title = "Neotest",
			status = status,
			percent = percent,
		})
	end

	local function update_notification()
		if active_count(true) == 0 then
			return
		end

		local total, completed = counts()
		local percent = total > 0 and math.floor(completed * 100 / total + 0.5) or nil
		emit_progress(progress_text(false), "running", percent)
	end

	local function finish_notification()
		local _, _, _, failed = counts()
		local status = (failed > 0 or has_visible_runs(true)) and "failed" or "success"
		emit_progress(progress_text(true), status, 100)
		prune_finished_visible_runs()
	end

	local function position_type(id, adapter_id)
		local ok, node = pcall(client.get_position, client, id, { adapter = adapter_id })
		return ok and node and node:data().type or nil
	end

	local function prune_pending_runs()
		local now = vim.uv.now()
		for i = #pending_runs, 1, -1 do
			if now - pending_runs[i].created_at > pending_run_ttl_ms then
				table.remove(pending_runs, i)
			end
		end
	end

	local function consume_pending_run(root_id, all_ids)
		prune_pending_runs()
		local all_id_count = vim.tbl_count(all_ids)
		for index, pending in ipairs(pending_runs) do
			if pending.root_id == root_id and pending.id_count == all_id_count then
				local all_match = true
				for id in pairs(pending.ids) do
					all_match = all_match and all_ids[id]
				end
				if all_match then
					table.remove(pending_runs, index)
					return pending.suppress_notification
				end
			end
		end
		return false
	end

	local function handle_run(adapter_id, root_id, position_ids)
		if active_count() == 0 then
			state.runs = {}
		end

		local all_ids, test_ids = {}, {}
		for _, id in ipairs(position_ids or {}) do
			all_ids[id] = true
			if position_type(id, adapter_id) == "test" then
				test_ids[#test_ids + 1] = id
			end
		end
		if root_id ~= nil then
			all_ids[root_id] = true
		end
		local count_ids = #test_ids > 0 and test_ids or (position_ids or {})
		if #count_ids == 0 and root_id ~= nil then
			count_ids = { root_id }
		end

		state.next_seq = state.next_seq + 1
		local suppress_notification = consume_pending_run(root_id, all_ids)

		local run = {
			adapter_id = adapter_id,
			root_id = root_id,
			active = true,
			all_ids = all_ids,
			all_id_count = vim.tbl_count(all_ids),
			count_ids = {},
			count_id_count = #count_ids,
			results = {},
			seq = state.next_seq,
			suppress_notification = suppress_notification,
			total = #count_ids,
		}
		for _, id in ipairs(count_ids) do
			run.count_ids[id] = true
		end
		state.runs[run.seq] = run
		if not suppress_notification then
			update_notification()
		end
	end

	local function set_contains_all(superset, subset)
		for id in pairs(subset or {}) do
			if not superset[id] then
				return false
			end
		end
		return true
	end

	local function same_set(left, left_count, right, right_count)
		return left_count == right_count and set_contains_all(left, right)
	end

	local function same_run_id_sets(left, right)
		return same_set(left.all_ids, left.all_id_count, right.all_ids, right.all_id_count)
			and same_set(left.count_ids, left.count_id_count, right.count_ids, right.count_id_count)
	end

	local function run_id_sets_strict_subset(left, right)
		return set_contains_all(right.all_ids, left.all_ids)
			and set_contains_all(right.count_ids, left.count_ids)
			and (left.all_id_count < right.all_id_count or left.count_id_count < right.count_id_count)
	end

	client.listeners.run = vim.schedule_wrap(handle_run)

	local function matching_runs(adapter_id, results, require_all)
		local matches = {}
		for _, run in pairs(state.runs) do
			if run.active and run.adapter_id == adapter_id then
				local any, all = false, true
				for id in pairs(results or {}) do
					local has_id = run.all_ids[id] or run.count_ids[id]
					any = any or has_id
					all = all and has_id
				end
				if any and (not require_all or all) then
					matches[#matches + 1] = run
				end
			end
		end
		table.sort(matches, function(a, b)
			if a.total ~= b.total then
				return a.total < b.total
			end
			return a.seq < b.seq
		end)
		return matches
	end

	local function results_match_count_set(run, result_ids, result_count)
		return same_set(run.count_ids, run.count_id_count, result_ids, result_count)
	end

	local function final_result_owner(matches, visible_matches, result_ids, result_count)
		if #visible_matches == 0 then
			return matches[1]
		end

		for _, run in ipairs(matches) do
			if run.suppress_notification and results_match_count_set(run, result_ids, result_count) then
				local has_visible_duplicate = false
				local has_visible_superset = false
				for _, visible in ipairs(visible_matches) do
					if same_run_id_sets(run, visible) then
						has_visible_duplicate = true
						break
					elseif run_id_sets_strict_subset(run, visible) then
						has_visible_superset = true
					end
				end
				if has_visible_superset and not has_visible_duplicate then
					return run
				end
			end
		end

		-- Neotest 5.20 does not expose a run ID/strategy here. If suppressed
		-- and visible runs have identical ID sets, ownership is inherently
		-- ambiguous, so keep the documented visible-first behavior.
		return visible_matches[1]
	end

	local function apply_results(run, results)
		for id, result in pairs(results or {}) do
			if status_key(result.status) == "failed" then
				run.terminal_failed = true
			end
			if run.count_ids[id] or run.total == 0 then
				run.results[id] = result
			end
		end
	end

	local function oldest_active_run(adapter_id, visible_only)
		local oldest = nil
		for _, run in pairs(state.runs) do
			if
				run.active
				and run.adapter_id == adapter_id
				and (not visible_only or not run.suppress_notification)
				and (not oldest or run.seq < oldest.seq)
			then
				oldest = run
			end
		end
		return oldest
	end

	local function handle_results(adapter_id, results, partial)
		local has_results = next(results or {}) ~= nil
		local result_ids = {}
		local result_count = 0
		for id in pairs(results or {}) do
			result_ids[id] = true
			result_count = result_count + 1
		end
		local matches = has_results and matching_runs(adapter_id, results, not partial) or {}
		if not partial and #matches == 0 then
			local fallback = nil
			if has_results then
				fallback = matching_runs(adapter_id, results, false)[1]
			else
				-- Neotest 5.20 final result events may omit run identity. Prefer
				-- visible progress when present so an older suppressed DAP run cannot
				-- strand a later normal run's sticky notification.
				fallback = oldest_active_run(adapter_id, true) or oldest_active_run(adapter_id)
			end
			if fallback then
				matches = { fallback }
			end
		end
		local visible_changed = false
		local visible_matches = {}
		for _, run in ipairs(matches) do
			if not run.suppress_notification then
				visible_matches[#visible_matches + 1] = run
			end
		end
		local target_matches = #visible_matches > 0 and visible_matches or matches
		if partial then
			-- Neotest 5.20 exposes adapter/root/position IDs but no run ID.
			-- Partial result ownership is therefore ambiguous for exact duplicate or
			-- shared-position runs. Suppressed and visible overlaps cannot be safely
			-- disambiguated, so ignore those partial counts and let the final result
			-- resolve visible progress instead of streaming DAP counts into the UI.
			if #visible_matches == 0 or #visible_matches == #matches then
				for _, run in ipairs(target_matches) do
					apply_results(run, results)
					visible_changed = visible_changed or not run.suppress_notification
				end
			end
		elseif #matches > 0 then
			-- A final results event belongs to one completed run_tree call. Pick the
			-- smallest active matching run, but keep visible-first behavior for exact
			-- duplicate suppressed/visible ID sets because Neotest 5.20 exposes no run
			-- ID or strategy in result events. When a suppressed DAP run has an exact
			-- count-set match that is a strict subset of visible supersets, consume the
			-- result there so it cannot update or finish the visible popup.
			local run = final_result_owner(matches, visible_matches, result_ids, result_count)
			apply_results(run, results)
			run.active = false
			visible_changed = not run.suppress_notification
		end

		if active_count(true) == 0 then
			if has_visible_runs() then
				finish_notification()
			elseif active_count() == 0 then
				state.runs = {}
			end
		elseif visible_changed then
			update_notification()
		end
	end

	client.listeners.results = vim.schedule_wrap(handle_results)
end

return M
